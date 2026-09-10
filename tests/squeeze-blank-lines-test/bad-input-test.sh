#!/bin/sh

# Tests that `squeeze-blank-lines` rejects an input file that it cannot read,
# rather than creating or truncating it.
#
# `squeeze-blank-lines FILE` edits FILE in place, so a read failure must not
# lead to a write.  Without this check, `squeeze-blank-lines nosuch.txt`
# created an empty `nosuch.txt` and exited with status 0, and a read error on
# an existing file destroyed its contents while reporting success.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
SQUEEZE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/squeeze-blank-lines"

work="$(mktemp -d)"
trap 'chmod -R u+rwX "$work" 2> /dev/null; rm -rf "$work"' EXIT HUP INT TERM

status=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  status=1
}

### A nonexistent file is not created, and the exit status is nonzero.

if "$SQUEEZE" "$work/nosuch.txt" 2> /dev/null; then
  fail "zero exit status for a nonexistent file"
else
  pass "nonzero exit status for a nonexistent file"
fi
if [ -e "$work/nosuch.txt" ]; then
  fail "created a nonexistent input file"
else
  pass "did not create a nonexistent input file"
fi

### A directory is not accepted as an input file.

mkdir "$work/dir"
if "$SQUEEZE" "$work/dir" 2> /dev/null; then
  fail "zero exit status for a directory"
else
  pass "nonzero exit status for a directory"
fi

### An unreadable file keeps its contents.

# check_unreadable MODE: creates a file with permissions MODE and one line of
# contents, runs `squeeze-blank-lines` on it, and checks that the script
# failed and left the contents alone.  Mode 200 is the interesting case:  the
# script cannot read the file but can write it, which is the shape of any read
# failure on a writable file.
check_unreadable() {
  mode="$1"
  file="$work/unreadable-$mode.txt"
  printf 'contents\n' > "$file"
  chmod "$mode" "$file"
  if "$SQUEEZE" "$file" 2> /dev/null; then
    fail "zero exit status for a mode-$mode file"
  else
    pass "nonzero exit status for a mode-$mode file"
  fi
  chmod u+rw "$file"
  if [ "$(cat "$file")" = "contents" ]; then
    pass "did not truncate a mode-$mode input file"
  else
    fail "truncated a mode-$mode input file"
  fi
}

# root can read a mode-000 file, so this part of the test would not test
# anything.  Skipping is better than failing.
if [ "$(id -u)" = 0 ]; then
  echo "$(basename -- "$0"): skipping the unreadable-file tests, because it is running as root."
else
  check_unreadable 000
  check_unreadable 200
fi

### A readable file is still edited in place.

printf '\n\nhello\n\n\n\nworld\n\n' > "$work/good.txt"
if "$SQUEEZE" "$work/good.txt"; then
  pass "zero exit status for a readable file"
else
  fail "nonzero exit status for a readable file"
fi
if [ "$(cat "$work/good.txt")" = "$(printf 'hello\n\nworld')" ]; then
  pass "edited a readable file in place"
else
  fail "did not edit a readable file in place"
  cat "$work/good.txt"
fi

exit "$status"
