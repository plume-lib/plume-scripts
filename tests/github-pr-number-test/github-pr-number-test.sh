#!/bin/sh

# Tests that the scripts derive a GitHub pull request number from
# GITHUB_REF_NAME only when GITHUB_REF_NAME actually names one.
#
# GITHUB_REF_NAME is like "40/merge" in a GitHub Actions `pull_request` event,
# but in a `pull_request_target` or `workflow_run` event -- which are pull
# request events too, and which do set GITHUB_HEAD_REF -- it is a branch name
# such as "master".  The scripts used to compute
# `GITHUB_PR_NUMBER=${GITHUB_REF_NAME%/merge}` with no check, and then request
# `https://api.github.com/repos/OWNER/REPO/pulls/master`.  That URL names no
# pull request: it spends one of the 60 unauthenticated requests per hour, and
# it 404s, so the organization has to come from a fallback anyway.
#
# The test supplies a stub `curl` and `wget` that log the URLs they are asked
# for, so that it needs no network and can check which requests were made.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

# The scripts need this, and skipping is better than failing:  a missing
# prerequisite is not a defect in the scripts.
if [ -z "$(command -v jq 2> /dev/null)" ]; then
  echo "$(basename -- "$0"): skipping, because jq is not installed."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

### A repository that looks like a GitHub Actions checkout

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
# The scripts ask origin for its default branch, so give this clone an origin.
# It is local, so that this test does not need the network.
git clone -q --bare . "$work/origin.git"
git remote add origin "$work/origin.git"
git fetch -q origin
git remote set-head origin main
SHA="$(git rev-parse HEAD)"

### The GitHub Actions event payload
#
# GitHub Actions writes this file for a pull request event, and the scripts
# read it when the API request does not yield an organization.  The head
# repository is a fork, so that a value taken from this file is distinguishable
# from one taken from this clone's origin.

cat > "$work/event.json" << 'EOF'
{
  "pull_request": {
    "number": 40,
    "head": {
      "ref": "feature-branch",
      "repo": { "owner": { "login": "forkorg" } }
    }
  }
}
EOF

### Stub `curl` and `wget`
#
# Each logs the URL it was asked for -- the last argument, in every call the
# scripts make -- and then answers as api.github.com does.  A pull request
# number is all digits; anything else names no pull request and gets a 404
# body, which is what the real API returns for ".../pulls/master".

mkdir "$work/bin"
for tool in curl wget; do
  cat > "$work/bin/$tool" << 'EOF'
#!/bin/sh
url=""
for arg in "$@"; do url="$arg"; done
printf '%s\n' "$url" >> "$REQUEST_LOG"
number=${url##*/}
case $number in
  '' | *[!0-9]*) printf '%s\n' '{"message":"Not Found"}' ;;
  *) printf '%s\n' '{"head":{"ref":"api-branch","repo":{"owner":{"login":"apiorg"}}}}' ;;
esac
EOF
  chmod +x "$work/bin/$tool"
done

### The test

status=0

# run SCRIPT REF-NAME: runs SCRIPT the way its documentation says to, in a
# simulated GitHub Actions `pull_request_target`-style job whose
# GITHUB_REF_NAME is REF-NAME, and prints CI_ORGANIZATION and CI_BRANCH on one
# line each.  The URLs that the job requested are left in $REQUEST_LOG.
run() {
  script="$1"
  ref_name="$2"
  : > "$work/requests.txt"
  # Run with an empty environment except for the GitHub Actions variables, so
  # that this test behaves the same whether or not it is itself running under
  # CI.  Other CI services' variables would send the scripts down other code
  # paths.  GITHUB_HEAD_REF is set, which is what makes this a pull request.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$work/bin:$PATH" HOME="$HOME" \
    REQUEST_LOG="$work/requests.txt" \
    GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request_target \
    GITHUB_BASE_REF=main GITHUB_HEAD_REF=feature-branch \
    GITHUB_REF_NAME="$ref_name" GITHUB_REPOSITORY=testorg/testrepo \
    GITHUB_SHA="$SHA" GITHUB_EVENT_PATH="$work/event.json" \
    sh -c '
      cd "$1" || exit 2
      if [ "$3" = "set-ci-org-and-branch" ]; then
        CI_DEFAULT_ORGANIZATION=testorg
        . "$2/$3" || exit 2
      else
        eval "$("$2/$3" testorg)" || exit 2
      fi
      printf "%s\n%s\n" "$CI_ORGANIZATION" "$CI_BRANCH"
    ' sh "$work/repo" "$PLUME_SCRIPTS" "$script" 2> /dev/null
}

# check DESCRIPTION REF-NAME EXPECTED-ORG EXPECTED-BRANCH EXPECTED-REQUESTS:
# checks that every script sets CI_ORGANIZATION and CI_BRANCH as given, and
# requests exactly the URLs in EXPECTED-REQUESTS (one per line, possibly none),
# when GITHUB_REF_NAME is REF-NAME.
check() {
  description="$1"
  ref_name="$2"
  expected_org="$3"
  expected_branch="$4"
  expected_requests="$5"
  for script in ci-org-and-branch set-ci-org-and-branch; do
    output=""
    if ! output="$(run "$script" "$ref_name")"; then
      echo "FAIL: $script: nonzero exit status for $description"
      status=1
      continue
    fi
    actual_org="$(printf '%s\n' "$output" | sed -n 1p)"
    actual_branch="$(printf '%s\n' "$output" | sed -n 2p)"
    actual_requests="$(cat "$work/requests.txt")"
    if [ "$actual_org" = "$expected_org" ] \
      && [ "$actual_branch" = "$expected_branch" ] \
      && [ "$actual_requests" = "$expected_requests" ]; then
      echo "PASS: $script with $description"
    else
      echo "FAIL: $script with $description"
      echo "  GITHUB_REF_NAME: $ref_name"
      echo "  expected CI_ORGANIZATION: $expected_org"
      echo "  actual   CI_ORGANIZATION: $actual_org"
      echo "  expected CI_BRANCH: $expected_branch"
      echo "  actual   CI_BRANCH: $actual_branch"
      echo "  expected requests: $expected_requests"
      echo "  actual   requests: $actual_requests"
      status=1
    fi
  done
}

# A `pull_request` event:  GITHUB_REF_NAME does name a pull request, so the
# scripts do request it and do use the answer.
check "a pull request ref name" "40/merge" apiorg feature-branch \
  "https://api.github.com/repos/testorg/testrepo/pulls/40"

# A `pull_request_target` event:  GITHUB_REF_NAME is the base branch.  No
# request is made, and the organization comes from the event payload.
check "a base branch ref name" main forkorg feature-branch ""

# The same, for a base branch whose name ends in "/merge".
check "a base branch named release/merge" release/merge forkorg feature-branch ""

exit "$status"
