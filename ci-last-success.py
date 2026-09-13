#!/usr/bin/env python3
"""Outputs the SHA commit id of a successful CI job.

Usage:  ci-last-success [options] ORG REPO [CANDIDATE]

Outputs the SHA commit id corresponding to the most recent successful CI job
that is CANDIDATE (a SHA hash) or earlier.
Works for any CI system that reports to GitHub, either as a commit status
(as Travis CI does) or as a check run (as Azure Pipelines and GitHub Actions do).

Options: --max-commits=N means to examine at most N commits; the default is
             100.  0 means no limit.
         --debug means to print diagnostic output to standard error.

Requires the Python requests module to be installed, which you can do via:
  pip install requests
"""

# This script makes at least one GitHub API request per commit that it
# examines:  one or more for the check runs and, unless those show that CI
# failed, one for the commit statuses.
# GitHub permits only 60 unauthenticated requests per hour, so:
#  * If environment variable GITHUB_PAT or GH_TOKEN is set when this script is
#    called, it is used as a GitHub Personal Access Token when making GitHub
#    API calls.  This can avoid "403 rate limit exceeded" failures.  The token
#    needs no permission beyond reading the repository:  if it may not read the
#    repository's check runs, this script uses only the commit statuses.
#  * At most --max-commits commits are examined, so that a repository whose
#    last successful job is far in the past cannot consume the whole quota.
#  * A request that fails transiently (including because of throttling or a
#    network-level error) is retried a few times, with exponential backoff.
#  * A request that is refused because of the rate limit is reported with
#    advice:  to set GITHUB_PAT or GH_TOKEN if neither is set, or that the one
#    that is set is not being respected if GitHub ignored it.
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

# `__doc__` is None if Python was run with the `-OO` command-line option.
DESCRIPTION = __doc__.splitlines()[0] if __doc__ else PROGRAM

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
# that it is a rate limit (either the hourly quota being exhausted or the
# secondary rate limit) rather than, say, a nonexistent repository.
RETRIABLE_STATUS_CODES = (429, 500, 502, 503, 504)

# The environment variables that may hold a GitHub Personal Access Token, in
# the order in which they are consulted.
TOKEN_VARIABLES = ("GITHUB_PAT", "GH_TOKEN")

# GitHub's hourly rate limit for unauthenticated requests.  If GitHub reports
# this as the applied limit even though a token was sent, it ignored the token.
UNAUTHENTICATED_RATE_LIMIT = "60"


def parse_args() -> argparse.Namespace:
    """Parse the command-line arguments.

    Returns:
        the parsed command-line arguments.
    """
    parser = argparse.ArgumentParser(prog=PROGRAM, description=DESCRIPTION)
    parser.add_argument("--max-commits", type=int, default=DEFAULT_MAX_COMMITS)
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("org")
    parser.add_argument("repo")
    parser.add_argument("commit", nargs="?")
    args = parser.parse_args()
    if args.max_commits < 0:
        parser.error(f"--max-commits must be non-negative, not {args.max_commits}")
    return args


def token_variable() -> str | None:
    """Return the name of the environment variable that supplies the GitHub token.

    Returns:
        the name of the first of TOKEN_VARIABLES that is set to a non-empty
        value, or None if none of them is.
    """
    for variable in TOKEN_VARIABLES:
        if os.environ.get(variable):
            return variable
    return None


def auth_headers() -> dict[str, str]:
    """Return the HTTP headers for a GitHub API request.

    Returns:
        the HTTP headers, which contain an authorization token if one is set in
        the environment.
    """
    headers = {"Accept": "application/vnd.github+json"}
    # A GitHub Personal Access Token.  GitHub accepts both "Bearer <token>"
    # and "token <token>".
    variable = token_variable()
    if variable is not None:
        headers["Authorization"] = f"Bearer {os.environ[variable]}"
    return headers


def rate_limited(response: requests.Response) -> bool:
    """Return true if `response` is a refusal because the rate limit was exceeded.

    Returns:
        true if `response` is a refusal because the rate limit was exceeded.
    """
    if response.status_code not in (403, 429):
        return False
    return response.headers.get("x-ratelimit-remaining") == "0"


def secondary_rate_limited(response: requests.Response) -> bool:
    """Return true if `response` is a refusal because the secondary rate limit was exceeded.

    Returns:
        true if `response` is a refusal because the secondary rate limit was
        exceeded.  Unlike the primary (hourly) rate limit, GitHub signals this
        by a "retry-after" header rather than by an exhausted quota.
    """
    return response.status_code in (403, 429) and "retry-after" in response.headers


def retry_delay(response: requests.Response, default_delay: float) -> float | None:
    """Return how long to wait before retrying the request that produced `response`.

    Returns:
        the number of seconds to wait before retrying the request, or None if
        the request should not be retried.
    """
    if (
        response.status_code not in RETRIABLE_STATUS_CODES
        and not rate_limited(response)
        and not secondary_rate_limited(response)
    ):
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


def rate_limit_advice(response: requests.Response) -> str:
    """Return advice about the token environment variables, for a rate-limit refusal.

    Returns:
        advice about GITHUB_PAT and GH_TOKEN:  to set one if neither is set, or
        that the one that is set is not being respected if GitHub applied the
        unauthenticated rate limit to a request that was authenticated with it.
    """
    variable = token_variable()
    # GitHub reports the rate limit that it applied to the request.
    limit = response.headers.get("x-ratelimit-limit")
    if variable is None:
        return (
            "\nThis request was not authenticated, and the GitHub rate limit for"
            f" unauthenticated requests is {limit or UNAUTHENTICATED_RATE_LIMIT} per hour."
            f"\nSet environment variable {' or '.join(TOKEN_VARIABLES)} to a GitHub"
            " Personal Access Token to raise the limit."
        )
    if limit is None or limit == UNAUTHENTICATED_RATE_LIMIT:
        # GitHub applied the unauthenticated limit even though the request was
        # authenticated, so it did not accept the token.
        return (
            f"\nEnvironment variable {variable} is set, and its value was sent as a"
            " Bearer token, but GitHub is not respecting it:  it applied its rate"
            f" limit of {limit or UNAUTHENTICATED_RATE_LIMIT} requests per hour for"
            " unauthenticated requests."
            f"\nThe token in {variable} may be expired, revoked, or malformed."
        )
    return (
        f"\nEnvironment variable {variable} authenticated this request, but its"
        f" GitHub rate limit of {limit} requests per hour is exhausted."
        "\nWait for the limit to reset, or pass --max-commits to examine fewer commits."
    )


def request_error_message(url: str, response: requests.Response) -> str:
    """Return a message describing a failed request.

    Returns:
        a message describing the failed request `url` that produced `response`.
    """
    result = f"GET {url} {response.status_code} {response.headers} {response.text}"
    if rate_limited(response):
        result += rate_limit_advice(response)
    elif secondary_rate_limited(response) and token_variable() is None:
        # GitHub's secondary rate limits are more generous for authenticated
        # requests, so suggest a token for them too.
        result += (
            "\nGitHub applied a secondary rate limit to this unauthenticated request."
            f"\nSet environment variable {' or '.join(TOKEN_VARIABLES)} to a GitHub"
            " Personal Access Token to raise the limits."
        )
    return result


def get_url(url: str, permitted_failures: tuple[int, ...] = ()) -> requests.Response:
    """Issue a GET request for `url`, retrying transient failures.

    `permitted_failures` are HTTP status codes that the caller can proceed
    without, so a response with one of them is returned rather than raised on.

    Returns:
        the response, whose status code is 200 or is in `permitted_failures`.

    Raises:
        RuntimeError: if the request did not succeed.
    """
    delay = INITIAL_RETRY_SECONDS
    retries_left = MAX_RETRIES
    while True:
        try:
            response = requests.get(url, headers=auth_headers(), timeout=30)
        except requests.RequestException as exc:
            # A connection reset, timeout, or DNS failure is transient, so
            # retry it just as an unsuccessful HTTP status code is retried.
            if retries_left == 0:
                message = f"GET {url} {exc}"
                raise RuntimeError(message) from exc
            this_delay: float = delay
        else:
            if response.status_code == 200:
                return response
            if (
                response.status_code in permitted_failures
                and not rate_limited(response)
                and not secondary_rate_limited(response)
            ):
                # A rate limit is never a permitted failure:  proceeding without
                # the response would silently mis-report every commit examined.
                return response
            delay_or_none = retry_delay(response, delay)
            if delay_or_none is None or retries_left == 0 or delay_or_none > MAX_RETRY_SECONDS:
                # This means something went wrong, possibly rate-limiting.
                raise RuntimeError(request_error_message(url, response))
            this_delay = delay_or_none
        if DEBUG:
            print(
                f"Retrying {url} in {this_delay} seconds ({retries_left} retries left)",
                file=sys.stderr,
            )
        time.sleep(this_delay)
        retries_left -= 1
        delay *= 2


# Check run conclusions that are not failures.  A check run that was skipped,
# that is advisory ("neutral"), or that GitHub superseded ("stale") does not
# make the commit unsuccessful.
# However, only a "success" conclusion is evidence that a CI job actually ran.
SUCCESS_CONCLUSIONS = frozenset(("success", "neutral", "skipped", "stale"))

# The HTTP status codes with which GitHub may decline to say what a commit's
# check runs are:  the credential may read the repository but not its check runs
# (403), or the endpoint is unavailable for the repository (404).  Neither is
# evidence that CI failed, and this script worked without the check runs before
# it consulted them, so the commit statuses decide such a commit.  A 403 that is
# a rate limit is not tolerated; see `get_url`.
CHECK_RUNS_UNAVAILABLE_STATUS_CODES = (403, 404)

# The largest page size that the GitHub API permits.
CHECK_RUNS_PER_PAGE = 100


def github_api_get_or_none(url: str, permitted_failures: tuple[int, ...]) -> dict | None:
    """Return the JSON body of a GET request to the GitHub API, or None if it was refused.

    Returns:
        the JSON body of a GET request to the GitHub API, or None if GitHub
        refused the request with one of `permitted_failures`.
    """
    if DEBUG:
        print(url, file=sys.stderr)
    response = get_url(url, permitted_failures)
    if response.status_code != 200:
        if DEBUG:
            print(f"  refused with status {response.status_code}", file=sys.stderr)
        return None
    result: dict = response.json()
    return result


def github_api_get(url: str) -> dict:
    """Return the JSON body of a GET request to the GitHub API.

    Returns:
        the JSON body of a GET request to the GitHub API.
    """
    if DEBUG:
        print(url, file=sys.stderr)
    result: dict = get_url(url).json()
    return result


def check_runs_successful(api_prefix: str) -> bool | None:
    """Return what the check runs of the commit at `api_prefix` say about its CI.

    Unlike the commit statuses, the check runs are combined by this code rather than by
    GitHub, so every page of them must be read.  Reading only the first page would report
    a commit as successful when a check run beyond that page failed, which happens for a
    build matrix with more jobs than fit on a page.

    Returns:
        False if a check run failed or has not completed, True if a check run
        succeeded, or None if the check runs are evidence neither way:  the
        commit has none, none of them ran (each was skipped, advisory, or
        superseded), or GitHub would not say what they are.
    """
    result: bool | None = None
    page = 1
    check_runs_seen = 0
    while True:
        response = github_api_get_or_none(
            f"{api_prefix}/check-runs?per_page={CHECK_RUNS_PER_PAGE}&page={page}",
            CHECK_RUNS_UNAVAILABLE_STATUS_CODES,
        )
        if response is None:
            # GitHub would not say what the check runs are, so let the commit
            # statuses decide the commit, as this script did before it consulted
            # check runs at all.
            return None
        check_runs = response["check_runs"]
        for check_run in check_runs:
            if check_run["status"] != "completed":
                return False
            conclusion = check_run["conclusion"]
            if conclusion not in SUCCESS_CONCLUSIONS:
                return False
            if conclusion == "success":
                result = True
        check_runs_seen += len(check_runs)
        # The second disjunct guards against a nonterminating loop if `total_count`
        # exceeds the number of check runs that the API actually yields.
        if check_runs_seen >= response["total_count"] or not check_runs:
            return result
        page += 1


def successful(org: str, repo: str, sha: str) -> bool:
    """Return true if at least one CI job ran for `sha` and no CI job failed.

    A CI system reports to GitHub either as a commit status (as Travis CI does) or as a
    check run (as Azure Pipelines and GitHub Actions do).  Both must be consulted.
    Consulting only the commit statuses reports "state": "pending" -- the combined state
    of zero commit statuses -- for a commit whose check runs all completed successfully.

    Returns:
        true if at least one CI job ran for `sha` and no CI job failed.
    """
    api_prefix = f"https://api.github.com/repos/{org}/{repo}/commits/{sha}"

    # Consult the check runs before the commit statuses, because the check runs alone
    # can answer "no" and every commit that this script steps over is a "no".  The
    # repositories that motivate consulting check runs (those whose CI is GitHub Actions
    # or Azure Pipelines) have no commit statuses at all, so requesting the commit
    # statuses first would double the number of requests -- and the number of requests
    # is what limits how far back this script can search.
    check_runs = check_runs_successful(api_prefix)
    if check_runs is False:
        return False
    saw_a_job = check_runs is True

    # GitHub computes the combined `state` over every commit status, so a single
    # request suffices no matter how many commit statuses there are.
    statuses = github_api_get(f"{api_prefix}/status")
    if statuses["statuses"]:
        if statuses["state"] != "success":
            return False
        saw_a_job = True

    return saw_a_job


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


def head_commit() -> str:
    """Return the SHA of the current HEAD.

    Returns:
        the SHA of the current HEAD.

    Raises:
        RuntimeError: if the SHA could not be determined.
    """
    git_rev_parse_result = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, check=False
    )
    if git_rev_parse_result.returncode != 0:
        raise RuntimeError(git_rev_parse_result.stderr.decode("utf-8", errors="replace"))
    return git_rev_parse_result.stdout.rstrip().decode("utf-8")


def main() -> None:
    """Output the SHA commit id of a successful CI job."""
    global DEBUG
    args = parse_args()
    DEBUG = DEBUG or args.debug

    commit_arg: str = args.commit if args.commit is not None else head_commit()

    if DEBUG:
        print(f"commit_arg: {commit_arg}", file=sys.stderr)

    commit: str = commit_arg
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
            print(f"Testing {commit}", file=sys.stderr)
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
    try:
        main()
    except RuntimeError as exc:
        # An expected failure, such as an exhausted rate limit, deserves a
        # message on standard error rather than a stack trace.
        print(f"{PROGRAM}: {exc}", file=sys.stderr)
        sys.exit(1)
