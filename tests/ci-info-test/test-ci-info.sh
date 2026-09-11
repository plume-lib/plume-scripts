#!/bin/sh

# Tests that `ci-info` does not write a credential to its output:
#  * on the path where it cannot determine the start of the commit range, and
#  * when the origin URL embeds one, as "https://USER:TOKEN@github.com/org/repo".
# A client `eval`s the output, so a credential in it lands in the CI log, which
# is often readable by anyone who can see the job.

# Halt on error.
set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
CI_INFO="${SCRIPT_DIR}/../../ci-info"

if [ -z "$(command -v jq 2> /dev/null)" ]; then
  echo "test-ci-info.sh: skipping, because jq is not installed." >&2
  exit 0
fi

# A fake credential, which must not appear in the output.
SECRET="fake-credential-that-must-not-be-printed"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

# `ci-info` asks the GitHub API for the pull request.  These stubs make that
# request fail without using the network, which is the situation that leads to
# the dump of the environment.  Both tools are stubbed, because `ci-info` uses
# whichever one it finds.
mkdir "$tmpdir/bin"
for tool in curl wget; do
  printf '#!/bin/sh\nexit 1\n' > "$tmpdir/bin/$tool"
  chmod +x "$tmpdir/bin/$tool"
done

# A repository that lacks the pull request's base branch, so that `ci-info`
# cannot determine the start of the commit range locally either.
git init -q "$tmpdir/repo"
cd "$tmpdir/repo"
git config user.email "ci-info-test@example.com"
git config user.name "ci-info test"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
echo two > file.txt
git commit -q -a -m "Second commit"

# `env -i`, because the ambient environment might indicate a different CI
# platform, and might contain a real credential.
run_ci_info() {
  env -i \
    PATH="$tmpdir/bin:$PATH" \
    HOME="$tmpdir" \
    GITHUB_HEAD_REF="a-feature-branch" \
    GITHUB_BASE_REF="no-such-base-branch" \
    GITHUB_REF_NAME="1/merge" \
    GITHUB_REPOSITORY="no-such-organization/no-such-repository" \
    GITHUB_SHA="$(git rev-parse HEAD)" \
    GITHUB_PAT="$SECRET" \
    sh "$CI_INFO" "$@" an-organization
}

status=0

check_output() {
  description="$1"
  if grep -q -- "$SECRET" "$tmpdir/out.txt" "$tmpdir/err.txt"; then
    echo "test-ci-info.sh: FAILED: ${description} wrote a credential:" >&2
    grep -n -- "$SECRET" "$tmpdir/out.txt" "$tmpdir/err.txt" >&2
    status=1
  fi
  # Without this check, the test would also pass if `ci-info` printed nothing.
  if ! grep -q '^CI_COMMIT_RANGE=' "$tmpdir/out.txt"; then
    echo "test-ci-info.sh: FAILED: ${description} did not set CI_COMMIT_RANGE." >&2
    status=1
  fi
}

run_ci_info > "$tmpdir/out.txt" 2> "$tmpdir/err.txt"
check_output "ci-info"

# `--debug` asks for the dump, but not for the credentials in it.
run_ci_info --debug > "$tmpdir/out.txt" 2> "$tmpdir/err.txt"
check_output "ci-info --debug"

# git accepts a credential embedded in a URL, and a job that clones with one
# has it in `remote.origin.url`.  `ci-info` derives $CI_ORGANIZATION from that
# URL, so it must take the URL apart rather than strip a fixed prefix.
URL_SECRET="fake-url-credential-that-must-not-be-printed"
git config remote.origin.url \
  "https://a-user:${URL_SECRET}@github.com/an-organization/a-repository.git"
# `git remote show origin` and `git ls-remote` contact the remote.  A proxy
# that refuses connections makes them fail at once, without using the network.
git config http.proxy 'http://127.0.0.1:1'

check_organization() {
  description="$1"
  if grep -q -- "$URL_SECRET" "$tmpdir/out.txt" "$tmpdir/err.txt"; then
    echo "test-ci-info.sh: FAILED: ${description} wrote the origin URL's credential:" >&2
    grep -n -- "$URL_SECRET" "$tmpdir/out.txt" "$tmpdir/err.txt" >&2
    status=1
  fi
  if ! grep -q '^CI_ORGANIZATION=.an-organization.;' "$tmpdir/out.txt"; then
    echo "test-ci-info.sh: FAILED: ${description} did not set CI_ORGANIZATION to the URL's organization:" >&2
    grep -n '^CI_ORGANIZATION=' "$tmpdir/out.txt" >&2
    status=1
  fi
}

run_ci_info > "$tmpdir/out.txt" 2> "$tmpdir/err.txt"
check_organization "ci-info with a credential in the origin URL"

run_ci_info --debug > "$tmpdir/out.txt" 2> "$tmpdir/err.txt"
check_organization "ci-info --debug with a credential in the origin URL"

if [ "$status" -eq 0 ]; then
  echo "test-ci-info.sh: passed."
fi
exit "$status"
