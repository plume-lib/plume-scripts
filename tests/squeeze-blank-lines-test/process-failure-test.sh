#!/bin/sh

# Tests that `squeeze-blank-lines` notices a failure of any of the commands
# that process the data, rather than only of the last one.
#
# `squeeze-blank-lines FILE` edits FILE in place, so a processing failure must
# not lead to a write.  When the processing was one pipeline, `sh` has no
# `pipefail`, so a failure of the first `sed` went unnoticed:  the second `sed`
# succeeded on the empty input, and the empty result was written over FILE.
#
# The test makes a `sed` fail by putting a wrapper earlier on the PATH.  The
# wrapper fails for the given stage of processing and delegates to the real
# `sed` otherwise.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
SQUEEZE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/squeeze-blank-lines"

REAL_SED="$(command -v sed)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  status=1
}

mkdir "$work/bin"

# make_failing_sed SCRIPT:  creates $work/bin/sed, which exits with status 3
# when one of its arguments is SCRIPT, and otherwise runs the real `sed`.
make_failing_sed() {
  cat > "$work/bin/sed" << EOF
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = '$1' ]; then
    echo "sed: simulated failure" >&2
    exit 3
  fi
done
exec "$REAL_SED" "\$@"
EOF
  chmod +x "$work/bin/sed"
}

# check_stage SCRIPT DESCRIPTION:  checks that `squeeze-blank-lines` fails, and
# does not modify its input file, when the `sed` whose script is SCRIPT fails.
check_stage() {
  make_failing_sed "$1"
  file="$work/input.txt"
  printf '\n\nhello\n\n\n\nworld\n\n' > "$file"
  if PATH="$work/bin:$PATH" "$SQUEEZE" "$file" 2> /dev/null; then
    fail "zero exit status when $2 failed"
  else
    pass "nonzero exit status when $2 failed"
  fi
  if [ "$(cat "$file")" = "$(printf '\n\nhello\n\n\n\nworld')" ]; then
    pass "did not modify the input file when $2 failed"
  else
    fail "modified the input file when $2 failed"
    cat "$file"
  fi
}

check_stage '/[^[:blank:]]/,$!d' "removal of leading blank lines"
check_stage ':a' "removal of trailing blank lines"

exit "$status"
