#!/usr/bin/env python3
"""Outputs the SHA commit id of a successful CI job.

Usage:  ci-last-success [options] ORG REPO [CANDIDATE]

Outputs the SHA commit id corresponding to the most recent successful CI job
that is CANDIDATE (a SHA hash) or earlier.
Currently works only for Azure Pipelines.

Options: --max-commits=N means to examine at most N commits; the default is
             100.  0 means no limit.
         --debug means to print diagnostic output.

Requires the Python requests module to be installed, which you can do via:
  pip install requests
"""

# This script makes one GitHub API request per commit that it examines.
# GitHub permits only 60 unauthenticated requests per hour, so:
#  * If environment variable GITHUB_PAT or GH_TOKEN is set when this script is
#    called, it is used as a GitHub Personal Access Token when making GitHub
#    API calls.  This can avoid "403 rate limit exceeded" failures.
#  * At most --max-commits commits are examined, so that a repository whose
#    last successful job is far in the past cannot consume the whole quota.
#  * A request that fails transiently (including because of throttling) is
#    retried a few times, with exponential backoff.
# The script prints nothing to standard out, only to standard error, if it
# cannot determine a successful commit.

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import requests

PROGRAM = Path(__file__).name

DEBUG = False

# The default for the --max-commits command-line argument.  With no
# authentication, GitHub permits only 60 requests per hour.
DEFAULT_MAX_COMMITS = 100

# How many times to retry a request that failed transiently.
MAX_RETRIES = 3

# How long to wait before the first retry; this is doubled for each subsequent
# retry.  (A response that says how long to wait overrides this.)
INITIAL_RETRY_SECONDS = 1.0

# Don't wait longer than this before a retry.  A rate limit that resets in an
# hour should be reported, not waited for.
MAX_RETRY_SECONDS = 60.0

# The HTTP status codes that are worth retrying:  throttling and transient
# server-side failures.  403 is also retried, but only when its headers show
# that it is the rate limit rather than, say, a nonexistent repository.
RETRIABLE_STATUS_CODES = (429, 500, 502, 503, 504)


def parse_args() -> argparse.Namespace:
    """Parse the command-line arguments.

    Returns:
        the parsed command-line arguments.
    """
    parser = argparse.ArgumentParser(prog=PROGRAM, description=__doc__.splitlines()[0])
    parser.add_argument("--max-commits", type=int, default=DEFAULT_MAX_COMMITS)
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("org")
    parser.add_argument("repo")
    parser.add_argument("commit", nargs="?")
    args = parser.parse_args()
    if args.max_commits < 0:
        parser.error(f"--max-commits must be non-negative, not {args.max_commits}")
    return args


def auth_headers() -> dict[str, str]:
    """Return the HTTP headers for a GitHub API request.

    Returns:
        the HTTP headers, which contain an authorization token if one is set in
        the environment.
    """
    headers = {"Accept": "application/vnd.github+json"}
    # "GITHUB_PAT" is a GitHub Personal Access Token.  GitHub accepts both
    # "Bearer <token>" and "token <token>".
    token = os.environ.get("GITHUB_PAT") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def rate_limited(response: requests.Response) -> bool:
    """Return true if `response` is a refusal because the rate limit was exceeded.

    Returns:
        true if `response` is a refusal because the rate limit was exceeded.
    """
    if response.status_code not in (403, 429):
        return False
    return response.headers.get("x-ratelimit-remaining") == "0"


def retry_delay(response: requests.Response, default_delay: float) -> float | None:
    """Return how long to wait before retrying the request that produced `response`.

    Returns:
        the number of seconds to wait before retrying the request, or None if
        the request should not be retried.
    """
    if response.status_code not in RETRIABLE_STATUS_CODES and not rate_limited(response):
        return None
    # GitHub sends "retry-after" when it is throttling, and "x-ratelimit-reset"
    # (an epoch time) when the hourly quota is exhausted.
    retry_after = response.headers.get("retry-after")
    if retry_after is not None:
        try:
            return max(0.0, float(retry_after))
        except ValueError:
            pass
    reset = response.headers.get("x-ratelimit-reset")
    if reset is not None and rate_limited(response):
        try:
            return max(0.0, float(reset) - time.time())
        except ValueError:
            pass
    return default_delay


def request_error_message(url: str, response: requests.Response) -> str:
    """Return a message describing a failed request.

    Returns:
        a message describing the failed request `url` that produced `response`.
    """
    result = f"GET {url} {response.status_code} {response.headers} {response.text}"
    if (
        rate_limited(response)
        and not os.environ.get("GITHUB_PAT")
        and not os.environ.get("GH_TOKEN")
    ):
        result += (
            "\nThe GitHub rate limit for unauthenticated requests is 60 per hour."
            "\nSet environment variable GITHUB_PAT or GH_TOKEN to a GitHub"
            " Personal Access Token to raise it."
        )
    return result


def get_url(url: str) -> requests.Response:
    """Issue a GET request for `url`, retrying transient failures.

    Returns:
        the response, whose status code is 200.

    Raises:
        RuntimeError: if the request did not succeed.
    """
    delay = INITIAL_RETRY_SECONDS
    retries_left = MAX_RETRIES
    while True:
        response = requests.get(url, headers=auth_headers(), timeout=30)
        if response.status_code == 200:
            return response
        this_delay = retry_delay(response, delay)
        if this_delay is None or retries_left == 0 or this_delay > MAX_RETRY_SECONDS:
            # This means something went wrong, possibly rate-limiting.
            raise RuntimeError(request_error_message(url, response))
        if DEBUG:
            print(f"Retrying {url} in {this_delay} seconds ({retries_left} retries left)")
        time.sleep(this_delay)
        retries_left -= 1
        delay *= 2


### PROBLEM: api.github.com is returning   "state": "pending"   for commits with completed CI jobs.
### Maybe I need to screen-scrape a different github.com page.  :-(
def successful(org: str, repo: str, sha: str) -> bool:
    """Return true if `sha`'s CI job succeeded.

    Returns:
        true if `sha`'s CI job succeeded.
    """
    # message=commit['commit']['message']
    url_status = f"https://api.github.com/repos/{org}/{repo}/commits/{sha}/status"
    if DEBUG:
        print(url_status)
    resp_status = get_url(url_status)
    state = resp_status.json()["state"]
    result: bool = state == "success"
    return result


def parent(sha: str) -> str | None:
    """Return the SHA of the first parent of the given SHA.  Return None if this is the root.

    Returns:
        the SHA of the first parent of the given SHA, or None.
    """
    get_parent_result = subprocess.run(
        ["git", "rev-parse", sha + "^"], capture_output=True, check=False
    )
    if get_parent_result.returncode != 0:
        return None
    return get_parent_result.stdout.rstrip().decode("utf-8")


def main() -> None:
    """Output the SHA commit id of a successful CI job."""
    global DEBUG
    args = parse_args()
    DEBUG = DEBUG or args.debug

    commit_arg = args.commit
    if commit_arg is None:
        git_rev_parse_result = subprocess.run(
            ["git", "rev-parse", "HEAD"], capture_output=True, check=False
        )
        if git_rev_parse_result.returncode != 0:
            raise RuntimeError(git_rev_parse_result.stderr.decode("utf-8", errors="replace"))
        commit_arg = git_rev_parse_result.stdout.rstrip().decode("utf-8")

    if DEBUG:
        print(f"commit_arg: {commit_arg}")

    commit = commit_arg
    examined = 0
    while True:
        if args.max_commits != 0 and examined == args.max_commits:
            print(
                f"No successful CI job found in the {examined} commits at or before"
                f" {commit_arg}; use --max-commits to examine more.",
                file=sys.stderr,
            )
            sys.exit(1)
        if DEBUG:
            print(f"Testing {commit}")
        examined += 1
        if successful(args.org, args.repo, commit):
            print(f"{commit}")
            sys.exit(0)
        the_parent = parent(commit)
        if the_parent is None:
            print(f"No successful CI job found at or before {commit_arg}", file=sys.stderr)
            sys.exit(1)
        commit = the_parent


if __name__ == "__main__":
    main()
