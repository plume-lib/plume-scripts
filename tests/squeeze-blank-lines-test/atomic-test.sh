#!/bin/bash

# Tests that `squeeze-blank-lines FILE` rewrites FILE atomically:  a failure
# partway through the write leaves the original contents in place.
#
# Before this was fixed, the script truncated FILE and then wrote to it, so an
# interrupted or failed write destroyed the file.  The test provokes a failed
# write with `ulimit -f`, which is the same failure that a full filesystem
# produces.
#
# The test also checks the properties that the rewrite must not lose:  the
# file's permissions, a symbolic link to it, and no leftover temporary files.
#
# This test uses `bash` rather than `sh` because `checkbashisms` rejects
# `ulimit`.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
SQUEEZE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/squeeze-blank-lines"

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

# Outputs the number of temporary files that `squeeze-blank-lines` left in
# directory $1.
count_tempfiles() {
  count=0
  for tempfile in "$1"/squeeze-blank-lines.*; do
    if [ -e "$tempfile" ]; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

### A write that fails partway through does not destroy the input file.

# The file must be larger than the file-size limit imposed below, which is 1
# block:  512 bytes in some shells, 1024 in others.
i=0
while [ "$i" -lt 200 ]; do
  echo "line $i ........................................"
  i=$((i + 1))
done > "$work/big.txt"
cp "$work/big.txt" "$work/big-expected.txt"

# `ulimit` affects only the subshell.  The shell that exceeds the limit is
# killed by SIGXFSZ if the signal is not handled, so ignore the exit status
# and the message that the killing shell prints.
(
  ulimit -f 1
  "$SQUEEZE" "$work/big.txt" 2> /dev/null
) 2> /dev/null || true
if cmp -s "$work/big.txt" "$work/big-expected.txt"; then
  pass "kept the input file's contents when the write failed"
else
  fail "destroyed the input file when the write failed"
fi

# The temporary file that the failed write used is not left behind.
leftovers="$(count_tempfiles "$work")"
if [ "$leftovers" = 0 ]; then
  pass "left no temporary file behind after a failed write"
else
  fail "left $leftovers temporary file(s) behind after a failed write"
fi

### A successful rewrite preserves the file's permissions.

printf '\n\nhello\n\n\n\nworld\n\n' > "$work/modes.txt"
chmod 640 "$work/modes.txt"
"$SQUEEZE" "$work/modes.txt"
if [ -n "$(find "$work/modes.txt" -perm 640 -print)" ]; then
  pass "preserved the input file's permissions"
else
  fail "changed the input file's permissions"
fi

### A successful rewrite does not replace a symbolic link by a regular file.

printf '\n\nhello\n\n\n\nworld\n\n' > "$work/target.txt"
ln -s target.txt "$work/link.txt"
"$SQUEEZE" "$work/link.txt"
if [ -L "$work/link.txt" ]; then
  pass "did not replace a symbolic link by a regular file"
else
  fail "replaced a symbolic link by a regular file"
fi
if [ "$(cat "$work/target.txt")" = "$(printf 'hello\n\nworld')" ]; then
  pass "rewrote the file that a symbolic link refers to"
else
  fail "did not rewrite the file that a symbolic link refers to"
  cat "$work/target.txt"
fi

### A successful rewrite leaves no temporary file behind.

leftovers="$(count_tempfiles "$work")"
if [ "$leftovers" = 0 ]; then
  pass "left no temporary file behind after a successful write"
else
  fail "left $leftovers temporary file(s) behind after a successful write"
fi

exit "$status"
