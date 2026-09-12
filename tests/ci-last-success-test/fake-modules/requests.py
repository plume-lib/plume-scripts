"""A fake `requests` module, so that `ci-last-success.py` can be tested offline.

It logs each request to the file named by environment variable
FAKE_REQUESTS_LOG, one line per request, in the format

  GET URL auth=AUTHORIZATION-HEADER-OR-"NONE"

Environment variable FAKE_REQUESTS_RESPONSES is a whitespace-separated list of
response names, one per request; the last one is reused for any further
requests.  The response names are:

  success    an HTTP 200 response that reports a successful CI job
  pending    an HTTP 200 response that reports a pending CI job
  503        an HTTP 503 response, which is a transient failure
  ratelimit  an HTTP 403 response that says the unauthenticated rate limit
             (60 per hour) is exhausted and will not reset for an hour
  ratelimit-authenticated
             like `ratelimit`, but the exhausted limit is the authenticated
             one (5000 per hour), showing that GitHub honored the token

A response's body depends on whether the request is for a commit's statuses or
for its check runs, since `ci-last-success.py` requests both.  A `pending`
commit status is not the combined state of zero statuses, so `ci-last-success.py`
rejects such a commit without going on to request its check runs; that makes
`pending` cost exactly one request per commit examined.
"""

import os
import time
from pathlib import Path
from typing import Any

LOG = Path(os.environ["FAKE_REQUESTS_LOG"])

RESPONSES = os.environ.get("FAKE_REQUESTS_RESPONSES", "pending").split()


class Response:
    """A fake `requests.Response`."""

    def __init__(self, status_code: int, headers: dict[str, str], payload: Any) -> None:
        """Create a fake response with the given status code, headers, and payload."""
        self.status_code = status_code
        self.headers = headers
        self.text = str(payload)
        self.payload = payload

    def json(self) -> Any:
        """Return the response payload.

        Returns:
            the response payload.
        """
        return self.payload


def get(url: str, headers: dict[str, str] | None = None, timeout: float | None = None) -> Response:
    """Log the request and return the response that FAKE_REQUESTS_RESPONSES calls for.

    Returns:
        the canned response for this request.
    """
    # This fake makes no request, so the timeout is irrelevant; this assignment
    # documents that, and keeps the signature compatible with `requests.get`.
    _ = timeout
    if headers is None:
        headers = {}
    with LOG.open("a", encoding="utf-8") as log:
        log.write(f"GET {url} auth={headers.get('Authorization', 'NONE')}\n")
    with LOG.open(encoding="utf-8") as log:
        # This request has already been logged, so this is 0 for the first request.
        index = len(log.readlines()) - 1
    name = RESPONSES[min(index, len(RESPONSES) - 1)]
    check_runs = "/check-runs" in url
    if name == "success":
        if check_runs:
            return Response(
                200,
                {},
                {
                    "total_count": 1,
                    "check_runs": [
                        {"name": "build", "status": "completed", "conclusion": "success"}
                    ],
                },
            )
        return Response(200, {}, {"state": "success", "statuses": [{"state": "success"}]})
    if name == "pending":
        if check_runs:
            return Response(200, {}, {"total_count": 0, "check_runs": []})
        return Response(200, {}, {"state": "pending", "statuses": [{"state": "pending"}]})
    if name == "503":
        return Response(503, {}, "Service Unavailable")
    if name in ("ratelimit", "ratelimit-authenticated"):
        reset = str(int(time.time()) + 3600)
        limit = "5000" if name == "ratelimit-authenticated" else "60"
        headers = {
            "x-ratelimit-limit": limit,
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": reset,
        }
        return Response(403, headers, "API rate limit exceeded")
    msg = f"Unknown response name {name!r} in FAKE_REQUESTS_RESPONSES"
    raise AssertionError(msg)
