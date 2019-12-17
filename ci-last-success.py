#!/usr/bin/env python3

# Outputs the SHA commit id corresponding to the most recent successful CI job.
# Currently works only for Azure Pipelines, and only for the master branch.

import requests
import json
import pprint

org="typetools"
repo="checker-framework"

url_commits = 'https://api.github.com/repos/{}/{}/commits'.format(org, repo)
resp_commits = requests.get(url_commits)
if resp_commits.status_code != 200:
    # This means something went wrong.
    raise Exception('GET {} {} {}'.format(url_commits, resp_commits.status_code, resp_commits.headers))
for commit in resp_commits.json():
    sha=commit['sha']
    message=commit['commit']['message']
    print('{} {}'.format(sha, message))
    url_status = 'https://api.github.com/repos/{}/{}/commits/{}/status'.format(org, repo, sha)
    print('  url: {}'.format(url_status))
    resp_status = requests.get(url_status)
    if resp_status.status_code != 200:
        # This means something went wrong.
        raise Exception('GET {} {}'.format(url_status, resp_status.status_code))
    state=resp_status.json()['state']
    print('  {} {} {}'.format(state, sha, message))
