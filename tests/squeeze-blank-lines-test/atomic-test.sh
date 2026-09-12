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
# file's permissions (even those of a read-only file that the user owns),
# symbolic links to it, and no leftover temporary files.  Finally, it checks
# the two consequences of writing-then-renaming that the script documents:
# other hard links to the file keep the old contents, and rewriting a file
# requires write permission on its directory.
#
# This test uses `bash` rather than `sh` because `checkbashisms` rejects
# `ulimit`.

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

### A read-only file that the user owns is rewritten, keeping its permissions.

# The temporary file gets the input file's permissions only after its contents
# have been written; otherwise the write to a read-only temporary file fails.
printf '\n\nhello\n\n\n\nworld\n\n' > "$work/readonly.txt"
chmod 444 "$work/readonly.txt"
if "$SQUEEZE" "$work/readonly.txt"; then
  pass "zero exit status for a read-only file"
else
  fail "nonzero exit status for a read-only file"
fi
if [ "$(cat "$work/readonly.txt")" = "$(printf 'hello\n\nworld')" ]; then
  pass "rewrote a read-only file"
else
  fail "did not rewrite a read-only file"
  cat "$work/readonly.txt"
fi
if [ -n "$(find "$work/readonly.txt" -perm 444 -print)" ]; then
  pass "preserved a read-only file's permissions"
else
  fail "changed a read-only file's permissions"
  ls -l "$work/readonly.txt"
fi

### A chain of symbolic links is followed to the file at its end.

# `readlink -f` resolves a chain in one step, but it is a GNU extension, so
# the script resolves the links itself.
mkdir -p "$work/linkdir"
printf '\n\nhello\n\n\n\nworld\n\n' > "$work/linkdir/chain-target.txt"
ln -s chain-target.txt "$work/linkdir/chain-1.txt"
ln -s linkdir/chain-1.txt "$work/chain-2.txt"
"$SQUEEZE" "$work/chain-2.txt"
if [ -L "$work/chain-2.txt" ] && [ -L "$work/linkdir/chain-1.txt" ]; then
  pass "did not replace a chain of symbolic links by a regular file"
else
  fail "replaced a chain of symbolic links by a regular file"
fi
if [ "$(cat "$work/linkdir/chain-target.txt")" = "$(printf 'hello\n\nworld')" ]; then
  pass "rewrote the file at the end of a chain of symbolic links"
else
  fail "did not rewrite the file at the end of a chain of symbolic links"
  cat "$work/linkdir/chain-target.txt"
fi

### Other hard links to the file keep the old contents.

# This is a consequence of the atomic rewrite, which replaces the file rather
# than modifying it.  The script documents it; this test detects a change.
printf '\n\nhello\n\n\n\nworld\n\n' > "$work/hardlink-1.txt"
ln "$work/hardlink-1.txt" "$work/hardlink-2.txt"
"$SQUEEZE" "$work/hardlink-1.txt"
if [ "$(cat "$work/hardlink-2.txt")" = "$(printf '\n\nhello\n\n\n\nworld\n')" ]; then
  pass "left other hard links to the file untouched, as documented"
else
  fail "changed the contents of another hard link to the file"
  cat "$work/hardlink-2.txt"
fi

### A file in a directory that cannot be written is not rewritten.

# The temporary file is created in the file's directory, so rewriting the file
# requires write permission on the directory.  The script documents this.
# root can write any directory, so this would not test anything as root.
if [ "$(id -u)" = 0 ]; then
  echo "$(basename -- "$0"): skipping the read-only-directory test, because it is running as root."
else
  mkdir "$work/readonly-dir"
  printf 'contents\n\n\n' > "$work/readonly-dir/file.txt"
  chmod 555 "$work/readonly-dir"
  if "$SQUEEZE" "$work/readonly-dir/file.txt" 2> /dev/null; then
    fail "zero exit status for a file in a directory that cannot be written"
  else
    pass "nonzero exit status for a file in a directory that cannot be written"
  fi
  if [ "$(cat "$work/readonly-dir/file.txt")" = "contents" ]; then
    pass "kept the contents of a file in a directory that cannot be written"
  else
    fail "destroyed a file in a directory that cannot be written"
  fi
  chmod 755 "$work/readonly-dir"
fi

### A successful rewrite leaves no temporary file behind.

leftovers="$(count_tempfiles "$work")"
if [ "$leftovers" = 0 ]; then
  pass "left no temporary file behind after a successful write"
else
  fail "left $leftovers temporary file(s) behind after a successful write"
fi

exit "$status"
