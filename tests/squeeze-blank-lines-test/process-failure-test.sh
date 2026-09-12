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

# The `sed` scripts that `squeeze-blank-lines` runs, one per processing stage.
LEADING='/[^[:blank:]]/,$!d'
TRAILING=':a'

# A `sed` script that `squeeze-blank-lines` never runs.  A wrapper that fails
# only on it exercises the wrapper without making any stage fail.
NEVER='--no-such-sed-script--'

# make_failing_sed SCRIPT:  creates $work/bin/sed, which logs its arguments,
# exits with status 3 when one of them is SCRIPT, and otherwise runs the real
# `sed`.
make_failing_sed() {
  cat > "$work/bin/sed" << EOF
#!/bin/sh
for arg in "\$@"; do
  printf '%s\n' "\$arg" >> '$work/sed.log'
done
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

# write_input FILE:  fills FILE with text that has leading, internal, and
# trailing blank lines, so that every processing stage has work to do.
write_input() {
  printf '\n\nhello\n\n\n\nworld\n\n' > "$1"
}

### Positive control.
#
# With the wrapper installed but failing on nothing, `squeeze-blank-lines` must
# succeed and produce the expected output, and must invoke `sed` with each of
# the scripts that the checks below inject a failure into.
#
# Without this, the checks below would pass for the wrong reason if the wrapper
# never ran at all -- for instance if $work were on a `noexec` file system, so
# that both the wrapper and the real `sed` failed to execute, or if a later
# version of `squeeze-blank-lines` stopped using one of these `sed` scripts, or
# rejected the input before reaching the processing stages.  In each of those
# cases `squeeze-blank-lines` would exit nonzero without writing, which is what
# check_stage looks for, even if it had lost the ability to notice a `sed`
# failure.

make_failing_sed "$NEVER"
rm -f "$work/sed.log"
control="$work/control.txt"
write_input "$control"
if PATH="$work/bin:$PATH" "$SQUEEZE" "$control"; then
  pass "zero exit status when no stage failed"
else
  fail "nonzero exit status when no stage failed"
fi
if [ "$(cat "$control")" = "$(printf 'hello\n\nworld')" ]; then
  pass "squeezed the input file when no stage failed"
else
  fail "did not squeeze the input file when no stage failed"
  cat "$control"
fi

# check_invoked SCRIPT DESCRIPTION:  checks that the control run above passed
# SCRIPT to `sed`, so that failing on SCRIPT really does fail that stage.
check_invoked() {
  if [ -f "$work/sed.log" ] && grep -q -F -x -e "$1" "$work/sed.log"; then
    pass "ran the $2 sed script"
  else
    fail "never ran the $2 sed script, so failing on it tests nothing"
  fi
}

check_invoked "$LEADING" "removal of leading blank lines"
check_invoked "$TRAILING" "removal of trailing blank lines"

### Each stage's failure is noticed, and leaves the input file alone.

# check_stage SCRIPT DESCRIPTION:  checks that `squeeze-blank-lines` fails, and
# does not modify its input file, when the `sed` whose script is SCRIPT fails.
check_stage() {
  make_failing_sed "$1"
  file="$work/input.txt"
  write_input "$file"
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

check_stage "$LEADING" "removal of leading blank lines"
check_stage "$TRAILING" "removal of trailing blank lines"

exit "$status"
