#!/bin/sh

# Tests the three copies of the "redact tokens" function:  `redact_tokens` in
# `ci-info`, `_scoab_redact_tokens` in `set-ci-org-and-branch`, and
# `_sgr_redact_tokens` in `set-git-range`.  Each script has its own copy,
# because `ci-info` is frozen and because `set-ci-org-and-branch` unsets its
# functions before `set-git-range` runs.  Three copies drift:  the copy in
# `set-git-range` once lacked the substitution that redacts the credential in
# the userinfo of a URL, so a debug dump from a shallow single-branch checkout
# wrote "https://USER:TOKEN@github.com/org/repo" to the CI log, which is often
# readable by anyone who can see the job.  This test compares the copies
# against one expectation, so that a fix to one of them cannot be forgotten in
# the others.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

# The copies spell the placeholder differently:  "REDACTED" in `ci-info`, whose
# output the client `eval`s, and "<redacted>" in the "set-" scripts, whose
# output is prose on stderr.  The expected output below writes it "<P>", and
# the actual output is rewritten the same way, so that the comparison is about
# what is redacted rather than about how it is spelled.
normalize() {
  sed -e 's/<redacted>/<P>/g' -e 's/REDACTED/<P>/g'
}

# The input.  Each line is one line of a `set` or `env` dump.
cat > "$work/input.txt" << 'EOF'
GITHUB_PAT=a-personal-access-token
ACTIONS_RUNTIME_TOKEN=a-token-this-script-does-not-know-about
URL=https://a-user:a-url-credential@github.com/org/repo.git
QUOTED="https://a-user:a-url-credential@github.com/org/repo"
SQUOTED='https://a-user:a-url-credential@github.com/org/repo'
SCP=git@github.com:org/repo.git
PLAIN=https://github.com/org/repo
MSG=see http://example.com and mail me@example.org
QUERY=https://example.com?contact=me@example.org
FRAGMENT=https://example.com#mail-me@example.org
NOT_A_VARIABLE some text with an @ sign
EOF

# The expected output.  The credential is gone from every line that has one,
# and every other line is unchanged:  over-redacting destroys the very
# information that the dump exists to provide.  In particular, "MSG" keeps its
# text -- a userinfo cannot contain whitespace, so the match must not run from
# the URL to the "@" of the mail address and delete everything between them --
# "QUERY" and "FRAGMENT" keep theirs, because a userinfo ends at the first "/",
# "?", or "#", even in a URL that has no path -- and "SCP" keeps its "git@",
# which is a convention rather than a credential.
cat > "$work/expected.txt" << 'EOF'
GITHUB_PAT=<P>
ACTIONS_RUNTIME_TOKEN=<P>
URL=https://<P>@github.com/org/repo.git
QUOTED="https://<P>@github.com/org/repo"
SQUOTED='https://<P>@github.com/org/repo'
SCP=git@github.com:org/repo.git
PLAIN=https://github.com/org/repo
MSG=see http://example.com and mail me@example.org
QUERY=https://example.com?contact=me@example.org
FRAGMENT=https://example.com#mail-me@example.org
NOT_A_VARIABLE some text with an @ sign
EOF

# check SCRIPT FUNCTION: extracts FUNCTION from SCRIPT and runs the input
# through it.  Extracting the text, rather than sourcing the script, because
# `ci-info` and `set-git-range` do their work when sourced.
check() {
  script="$1"
  function_name="$2"
  extracted="$work/${function_name}.sh"
  sed -n "/^${function_name}() {/,/^}/p" "${PLUME_SCRIPTS}/${script}" > "$extracted"
  if ! grep -q "^${function_name}() {" "$extracted" || ! grep -q '^}' "$extracted"; then
    echo "FAIL: cannot extract ${function_name} from ${script}"
    status=1
    return
  fi
  # shellcheck disable=SC2016
  if ! sh -c '. "$1"; "$2"' sh "$extracted" "$function_name" \
    < "$work/input.txt" | normalize > "$work/actual.txt"; then
    echo "FAIL: nonzero exit status from ${function_name} in ${script}"
    status=1
    return
  fi
  if diff -u "$work/expected.txt" "$work/actual.txt" > "$work/diff.txt"; then
    echo "PASS: ${function_name} in ${script} redacts credentials and nothing else"
  else
    echo "FAIL: ${function_name} in ${script} redacts the wrong thing"
    sed -e 's/^/  /' "$work/diff.txt"
    status=1
  fi
}

check ci-info redact_tokens
check set-ci-org-and-branch _scoab_redact_tokens
check set-git-range _sgr_redact_tokens

exit "$status"
