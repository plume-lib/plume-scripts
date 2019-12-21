#!/usr/bin/env python3

# Usage:  ci-last-success ORG REPO
#
# Outputs the SHA commit id corresponding to the most recent successful CI job.
# Currently works only for Azure Pipelines, and only for the master branch.
#
# Requires the Python requests module to be installed

# This does no GitHub authentication, so it is limited to 60 requests
# per hour.  It fails if it goes over the limit.

import json
import pprint
import requests
import sys

if len(sys.argv) != 3:
    print('Wrong number of arguments {}, expected 2'.format(len(sys.argv)-1))
    sys.exit(2)

org=sys.argv[1]
repo=sys.argv[2]

url_commits = 'https://api.github.com/repos/{}/{}/commits'.format(org, repo)
resp_commits = requests.get(url_commits)
if resp_commits.status_code != 200:
    # This means something went wrong.
    raise Exception('GET {} {} {}'.format(url_commits, resp_commits.status_code, resp_commits.headers))
for commit in resp_commits.json():
    sha=commit['sha']
    # message=commit['commit']['message']
    url_status = 'https://api.github.com/repos/{}/{}/commits/{}/status'.format(org, repo, sha)
    resp_status = requests.get(url_status)
    if resp_status.status_code != 200:
        # This means something went wrong.
        raise Exception('GET {} {} {}'.format(url_status, resp_status.status_code, resp_status.headers))
    state=resp_status.json()['state']
    if (state == "success"):
        print('{}'.format(sha))
        sys.exit(0)

# Default to the penultimate commit.
print('{}'.format(resp_commits.json()[1]['sha']))
sys.exit(0)
