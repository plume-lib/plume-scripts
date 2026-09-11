"""A stub for the `requests` module, so that tests need no network access.

Responses are read from the JSON file named by the STUB_RESPONSES environment
variable: a map from URL to the JSON body that a GET of that URL returns.
A URL that is not in the map gets a 404 response.
"""

import json
import os
import pathlib


class Response:
    """The result of a stubbed HTTP request."""

    def __init__(self, status_code: int, body: object) -> None:
        """Create a Response with the given status code and JSON body."""
        self.status_code = status_code
        self.headers: dict[str, str] = {}
        self.body = body
        self.text = json.dumps(body)

    def json(self) -> object:
        """Return the response body, parsed as JSON.

        Returns:
            the response body, parsed as JSON.
        """
        return self.body


def get(url: str, **_kwargs: object) -> Response:
    """Return the canned response for `url`.

    Returns:
        the canned response for `url`.
    """
    responses = json.loads(pathlib.Path(os.environ["STUB_RESPONSES"]).read_text())
    if url not in responses:
        return Response(404, {"message": "Not Found"})
    return Response(200, responses[url])
