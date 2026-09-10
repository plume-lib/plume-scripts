#!/bin/sh

# Tests that the scripts do not mistake a GitHub API error response for an
# answer.
#
# A GitHub API request can fail -- the pull request does not exist, the
# request was throttled, the token expired -- and the response is then a JSON
# object that lacks the requested field.  `jq` prints the string "null" for a
# missing field, so a script that does not ask for "// empty" sets
# CI_ORGANIZATION or CI_BRANCH to the string "null" and reports success.  The
# client then acts on "null" as if it were an organization or a branch name.
#
# Each script must instead treat the missing field as missing:  either fall
# back to a value it can determine locally, or fail.

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

### A curl and a wget that answer every request the way GitHub answers a
### request for a pull request that does not exist.  They make this test
### independent of the network, and they let it provoke the error response
### without needing a repository that produces one.

mkdir "$work/bin"
cat > "$work/bin/curl" << 'EOF'
#!/bin/sh
printf '%s\n' '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
EOF
cp "$work/bin/curl" "$work/bin/wget"
chmod +x "$work/bin/curl" "$work/bin/wget"

### A repository, with a local origin so that this test does not need the
### network.

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
echo two >> file.txt
git commit -q -a -m "Second commit"
git clone -q --bare . "$work/origin.git"
git remote add origin "$work/origin.git"
git fetch -q origin
git remote set-head origin main

### The test

status=0

# check SCRIPT DESCRIPTION VAR=VALUE...: runs SCRIPT the way its documentation
# says to, in a CI environment described by the VAR=VALUE arguments and with
# the fake curl and wget above, and checks that no variable was set to the
# string "null".  A script that instead exits with a nonzero status has also
# detected the error response, so that is a pass too.
check() {
  script="$1"
  description="$2"
  shift 2
  actual=""
  # Run with an empty environment, so that this test behaves the same whether
  # or not it is itself running under CI:  a CI variable of this test's own
  # would send the script down a different code path.
  if ! actual="$(
    # The inner script is single-quoted on purpose:  its arguments are passed
    # positionally, so that this shell does not expand them into it.
    # shellcheck disable=SC2016
    env -i PATH="$work/bin:$PATH" HOME="$HOME" "$@" sh -c '
      cd "$1" || exit 2
      eval "$("$2/$3" testorg 2> /dev/null)" > /dev/null 2>&1 || exit 2
      printf "%s %s" "$CI_ORGANIZATION" "$CI_BRANCH"
    ' sh "$work/repo" "$PLUME_SCRIPTS" "$script"
  )"; then
    echo "PASS: $script under $description exited with a nonzero status"
    return
  fi
  case " $actual " in
    *" null "*)
      echo "FAIL: $script under $description used a jq \"null\" as a value"
      echo "  CI_ORGANIZATION and CI_BRANCH: $actual"
      status=1
      ;;
    *)
      echo "PASS: $script under $description"
      ;;
  esac
}

for script in ci-info ci-org-and-branch git-changes; do
  check "$script" "GitHub Actions" \
    GITHUB_ACTIONS=true GITHUB_HEAD_REF=feature GITHUB_REF_NAME=42/merge \
    GITHUB_REPOSITORY=testorg/testrepo
  check "$script" "Azure Pipelines" \
    AZURE_HTTP_USER_AGENT=VSTS_00000000-0000-0000-0000-000000000000 \
    BUILD_REASON=PullRequest BUILD_REPOSITORY_NAME=testorg/testrepo \
    SYSTEM_PULLREQUEST_PULLREQUESTNUMBER=42
done

exit "$status"
