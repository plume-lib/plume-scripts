#!/usr/bin/env python3
"""Outputs the SHA commit id of a successful CI job.

Usage:  ci-last-success ORG REPO [CANDIDATE]

Outputs the SHA commit id corresponding to the most recent successful CI job
that is CANDIDATE (a SHA hash) or earlier.
Works for any CI system that reports to GitHub, either as a commit status
(as Travis CI does) or as a check run (as Azure Pipelines and GitHub Actions do).

Requires the Python requests module to be installed, which you can do via:
  pip install requests
"""

# This does no GitHub authentication, so it is limited to 60 requests per
# hour.  It fails (and prints nothing to standard out, only to standard
# error) if it goes over the limit.

import subprocess
import sys

import requests

DEBUG = False
# DEBUG=True

if len(sys.argv) != 3 and len(sys.argv) != 4:
    print(
        f"Wrong number of arguments {len(sys.argv) - 1}, expected 2 or 3",
        file=sys.stderr,
    )
    sys.exit(2)

org = sys.argv[1]
repo = sys.argv[2]
commit_arg = None
if len(sys.argv) == 4:
    commit_arg = sys.argv[3]
else:
    git_rev_parse_result = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, check=False
    )
    if git_rev_parse_result.returncode == 0:
        commit_arg = git_rev_parse_result.stdout.rstrip().decode("utf-8")
    else:
        raise Exception(git_rev_parse_result.stderr.decode("utf-8", errors="replace"))

if DEBUG:
    print(f"commit_arg: {commit_arg}")


# Check run conclusions that are not failures.  A check run that was skipped
# or that is advisory ("neutral") does not make the commit unsuccessful.
# However, only a "success" conclusion is evidence that a CI job actually ran.
SUCCESS_CONCLUSIONS = frozenset(("success", "neutral", "skipped"))

# The largest page size that the GitHub API permits.
CHECK_RUNS_PER_PAGE = 100


def github_api_get(url: str) -> dict:
    """Return the JSON body of a GET request to the GitHub API.

    Returns:
        the JSON body of a GET request to the GitHub API.
    """
    if DEBUG:
        print(url)
    resp = requests.get(url, headers={"Accept": "application/vnd.github+json"}, timeout=30)
    if resp.status_code != 200:
        # This means something went wrong, possibly rate-limiting.
        msg = f"GET {url} {resp.status_code} {resp.headers} {resp.text}"
        raise Exception(msg)
    result: dict = resp.json()
    return result


def successful(sha: str) -> bool:
    """Return true if at least one CI job ran for `sha` and no CI job failed.

    A CI system reports to GitHub either as a commit status (as Travis CI does) or as a
    check run (as Azure Pipelines and GitHub Actions do).  Both must be consulted.
    Consulting only the commit statuses reports "state": "pending" -- the combined state
    of zero commit statuses -- for a commit whose check runs all completed successfully.

    Returns:
        true if at least one CI job ran for `sha` and no CI job failed.
    """
    api_prefix = f"https://api.github.com/repos/{org}/{repo}/commits/{sha}"
    saw_a_job = False

    # GitHub computes the combined `state` over every commit status, so a single
    # request suffices no matter how many commit statuses there are.
    statuses = github_api_get(f"{api_prefix}/status")
    if statuses["statuses"]:
        if statuses["state"] != "success":
            return False
        saw_a_job = True

    # Unlike the commit statuses, the check runs are combined by this code rather than
    # by GitHub, so every page of them must be read.  Reading only the first page would
    # report a commit as successful when a check run beyond that page failed, which
    # happens for a build matrix with more jobs than fit on a page.
    page = 1
    check_runs_seen = 0
    while True:
        response = github_api_get(
            f"{api_prefix}/check-runs?per_page={CHECK_RUNS_PER_PAGE}&page={page}"
        )
        check_runs = response["check_runs"]
        for check_run in check_runs:
            if check_run["status"] != "completed":
                return False
            conclusion = check_run["conclusion"]
            if conclusion not in SUCCESS_CONCLUSIONS:
                return False
            if conclusion == "success":
                saw_a_job = True
        check_runs_seen += len(check_runs)
        # The second disjunct guards against a nonterminating loop if `total_count`
        # exceeds the number of check runs that the API actually yields.
        if check_runs_seen >= response["total_count"] or not check_runs:
            return saw_a_job
        page += 1


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


commit = commit_arg
while True:
    if DEBUG:
        print(f"Testing {commit}")
    if successful(commit):
        print(f"{commit}")
        sys.exit(0)
    the_parent = parent(commit)
    if the_parent is None:
        print(f"No successful CI job found at or before {commit_arg}", file=sys.stderr)
        sys.exit(1)
    commit = the_parent
