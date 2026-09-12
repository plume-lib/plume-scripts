"""A fake `requests` module, so that `ci-last-success.py` can be tested offline.

If environment variable FAKE_REQUESTS_LOG is set, each request is logged to
that file, one line per request, in the format

  GET URL auth=AUTHORIZATION-HEADER-OR-"NONE"

Environment variable FAKE_REQUESTS_RESPONSES is either the name of a JSON file,
which answers every request, or a whitespace-separated list of built-in
response names, one per request, the last of which is reused for any further
requests.  A file name is used whole rather than split, so it may contain
whitespace.

The built-in responses are:

  success    an HTTP 200 response that reports a successful CI job
  pending    an HTTP 200 response that reports a pending CI job
  503        an HTTP 503 response, which is a transient failure
  ratelimit  an HTTP 403 response that says the unauthenticated rate limit
             (60 per hour) is exhausted and will not reset for an hour
  ratelimit-authenticated
             like `ratelimit`, but the exhausted limit is the authenticated
             one (5000 per hour), showing that GitHub honored the token
  forbidden  an HTTP 403 response that is a refusal of access rather than a
             rate limit, as GitHub sends when a credential may read a
             repository but not its check runs

The body of a built-in response depends on whether the request is for a
commit's check runs or for its statuses, since `ci-last-success.py` requests
both.  A `pending` check run has not completed, so `ci-last-success.py` rejects
such a commit without going on to request its commit statuses; that makes
`pending` cost exactly one request per commit examined.

A JSON file contains a map from URL to the JSON body that a GET of that URL
returns, with status 200.  A URL that is not in the map gets a 404 response.
Use a JSON file to say what CI results a specific commit has; use a built-in
response to say how the GitHub API behaves, regardless of the commit.
"""

import json
import os
import time
from pathlib import Path
from typing import Any

BUILT_IN_RESPONSES = (
    "success",
    "pending",
    "503",
    "ratelimit",
    "ratelimit-authenticated",
    "forbidden",
)

# The number of requests made so far, which selects from FAKE_REQUESTS_RESPONSES.
# `ci-last-success.py` runs as a fresh process per test, so this starts at 0 for
# each test.
requests_made = 0


class RequestException(Exception):  # ruff: ignore[error-suffix-on-exception-name]
    """A fake for `requests.RequestException`.

    `ci-last-success.py` names it in an `except` clause, so it must exist even
    though this fake never raises it.
    """


class Response:
    """A fake `requests.Response`."""

    def __init__(self, status_code: int, headers: dict[str, str], payload: Any) -> None:
        """Create a fake response with the given status code, headers, and payload."""
        self.status_code = status_code
        self.headers = headers
        self.payload = payload
        self.text = json.dumps(payload) if isinstance(payload, (dict, list)) else str(payload)

    def json(self) -> Any:
        """Return the response payload.

        Returns:
            the response payload.
        """
        return self.payload


def built_in_response(name: str, url: str) -> Response:
    """Return the built-in response with the given name, for a request to `url`.

    Returns:
        the built-in response with the given name.
    """
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
            return Response(
                200,
                {},
                {
                    "total_count": 1,
                    "check_runs": [{"name": "build", "status": "in_progress", "conclusion": None}],
                },
            )
        return Response(200, {}, {"state": "pending", "statuses": [{"state": "pending"}]})
    if name == "503":
        return Response(503, {}, "Service Unavailable")
    if name == "forbidden":
        # GitHub reports an unexhausted quota, which is what distinguishes this
        # refusal from a rate limit.
        return Response(
            403,
            {"x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4999"},
            {"message": "Resource not accessible by personal access token"},
        )
    reset = str(int(time.time()) + 3600)
    limit = "5000" if name == "ratelimit-authenticated" else "60"
    headers = {
        "x-ratelimit-limit": limit,
        "x-ratelimit-remaining": "0",
        "x-ratelimit-reset": reset,
    }
    return Response(403, headers, "API rate limit exceeded")


def file_response(file: str, url: str) -> Response:
    """Return the response that the JSON file `file` gives for `url`.

    Returns:
        the canned response for `url`, or a 404 response if the file omits it.
    """
    path = Path(file)
    if not path.is_file():
        msg = (
            f"FAKE_REQUESTS_RESPONSES names {file!r}, which is neither a built-in"
            f" response ({', '.join(BUILT_IN_RESPONSES)}) nor a readable file"
        )
        raise AssertionError(msg)
    responses = json.loads(path.read_text(encoding="utf-8"))
    if url not in responses:
        return Response(404, {}, {"message": "Not Found"})
    return Response(200, {}, responses[url])


def get(url: str, headers: dict[str, str] | None = None, timeout: float | None = None) -> Response:
    """Log the request and return the response that FAKE_REQUESTS_RESPONSES calls for.

    Returns:
        the canned response for this request.
    """
    # This fake makes no request, so the timeout is irrelevant; this assignment
    # documents that, and keeps the signature compatible with `requests.get`.
    _ = timeout
    global requests_made
    if headers is None:
        headers = {}
    log = os.environ.get("FAKE_REQUESTS_LOG")
    if log is not None:
        with Path(log).open("a", encoding="utf-8") as log_file:
            log_file.write(f"GET {url} auth={headers.get('Authorization', 'NONE')}\n")
    responses = os.environ.get("FAKE_REQUESTS_RESPONSES", "pending")
    # A file name is used whole, so that it may contain whitespace; a list of
    # built-in response names is split.
    names = [responses] if Path(responses).is_file() else responses.split()
    name = names[min(requests_made, len(names) - 1)]
    requests_made += 1
    if name in BUILT_IN_RESPONSES:
        return built_in_response(name, url)
    return file_response(name, url)
