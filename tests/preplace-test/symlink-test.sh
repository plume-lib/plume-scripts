#!/bin/sh

# Tests that `preplace` edits the file a symbolic link points to, rather than
# replacing the symbolic link by a regular file.
#
# `perl -i` unlinks the file it edits and creates a new one in its place, so a
# symbolic link given to it is destroyed:  the link becomes a regular file
# holding the edited contents, and the linked-to file is left unchanged.
# `preplace` avoids that by resolving each file name with `abs_path`, but it
# used to do so only for files named on the command line, not for the files
# found by directory traversal -- which is its default mode of operation.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PREPLACE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/preplace"

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

# check_symlink DESCRIPTION LINK TARGET: checks that LINK is still a symbolic
# link and that TARGET holds the replaced text.
check_symlink() {
  if [ -L "$2" ]; then
    pass "$1: left the symbolic link alone"
  else
    fail "$1: replaced the symbolic link by a regular file"
  fi
  if [ "$(cat "$3")" = "NEW" ]; then
    pass "$1: edited the linked-to file"
  else
    fail "$1: linked-to file contains $(cat "$3"), not NEW"
  fi
}

### A symbolic link found by directory traversal.

mkdir -p "$work/traversal/sub"
printf 'OLD\n' > "$work/traversal/sub/target.txt"
ln -s target.txt "$work/traversal/sub/link.txt"
(cd "$work/traversal" && "$PREPLACE" OLD NEW)
check_symlink "traversal" "$work/traversal/sub/link.txt" \
  "$work/traversal/sub/target.txt"

### A symbolic link, found by directory traversal, to a file outside the
### traversed directory.  Only the link is under the current directory, so the
### only way for the replacement to happen is through the link.

mkdir -p "$work/outside/sub"
printf 'OLD\n' > "$work/outside-target.txt"
ln -s ../../outside-target.txt "$work/outside/sub/link.txt"
(cd "$work/outside" && "$PREPLACE" OLD NEW)
check_symlink "outside target" "$work/outside/sub/link.txt" \
  "$work/outside-target.txt"

### A symbolic link named on the command line.  This case always worked; it is
### here so that a change to the explicit-file code path cannot regress it.

mkdir "$work/explicit"
printf 'OLD\n' > "$work/explicit/target.txt"
ln -s target.txt "$work/explicit/link.txt"
"$PREPLACE" OLD NEW "$work/explicit/link.txt"
check_symlink "explicit argument" "$work/explicit/link.txt" \
  "$work/explicit/target.txt"

### A file reachable both directly and through a symbolic link is edited once.
### Resolving the link makes the two names equal, so without deduplication the
### replacement would be applied twice.

mkdir "$work/twice"
printf 'a\n' > "$work/twice/target.txt"
ln -s target.txt "$work/twice/link.txt"
(cd "$work/twice" && "$PREPLACE" a aa)
if [ "$(cat "$work/twice/target.txt")" = "aa" ]; then
  pass "duplicate: applied the replacement once"
else
  fail "duplicate: target.txt contains $(cat "$work/twice/target.txt"), not aa"
fi

exit "$status"
