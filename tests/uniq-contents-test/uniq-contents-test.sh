#!/bin/sh

# Tests for `uniq-contents`.
#
# The unreadable-file tests are the interesting ones.  `uniq-contents` used
# to pipe the hashing command into `cut`, which discards the hashing
# command's exit status because `sh` has no `pipefail`.  An unreadable file
# therefore hashed to the empty string, which matches the "already seen"
# `case` pattern even on the first iteration (with `seen` empty, both the
# case word and the pattern are just spaces).  So every unreadable file --
# the first one included -- was silently dropped, and the exit status was 0.
# For a tool whose output is meant to be fed to another command, that is
# silent data loss.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
UNIQ="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/uniq-contents"

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

# check_output DESCRIPTION EXPECTED ACTUAL
check_output() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1"
    echo "  expected: $2"
    echo "  actual:   $3"
  fi
}

### Duplicate contents are removed, keeping the first file in argument order.

printf 'aaa\n' > "$work/a.txt"
printf 'bbb\n' > "$work/b.txt"
printf 'aaa\n' > "$work/a2.txt"
out="$("$UNIQ" "$work/a.txt" "$work/b.txt" "$work/a2.txt")"
check_output "keeps the first of a group of identical files" \
  "$(printf '%s\n%s' "$work/a.txt" "$work/b.txt")" "$out"

### Distinct files are all printed.

out="$("$UNIQ" "$work/a.txt" "$work/b.txt")"
check_output "prints all distinct files" \
  "$(printf '%s\n%s' "$work/a.txt" "$work/b.txt")" "$out"

### Empty files are just another group of identical contents.

: > "$work/empty1.txt"
: > "$work/empty2.txt"
out="$("$UNIQ" "$work/empty1.txt" "$work/empty2.txt")"
check_output "empty files are duplicates of one another" "$work/empty1.txt" "$out"

### A file name containing a space is one argument, not two.

printf 'fff\n' > "$work/has space.txt"
out="$("$UNIQ" "$work/has space.txt" "$work/a.txt")"
check_output "a file name containing a space" \
  "$(printf '%s\n%s' "$work/has space.txt" "$work/a.txt")" "$out"

### No arguments is not an error.

out_status=0
out="$("$UNIQ")" || out_status=$?
check_output "no arguments produces no output" "" "$out"
check_output "no arguments exits 0" "0" "$out_status"

### Unreadable files are reported, not silently dropped or deduplicated.

# root can read a mode-000 file, so this part of the test would not test
# anything.  Skipping is better than failing.
if [ "$(id -u)" = 0 ]; then
  echo "$(basename -- "$0"): skipping the unreadable-file tests, because it is running as root."
else
  printf 'ccc\n' > "$work/c.txt"
  printf 'ddd\n' > "$work/d.txt"
  chmod 000 "$work/c.txt" "$work/d.txt"

  if out="$("$UNIQ" "$work/a.txt" "$work/c.txt" "$work/d.txt" 2> "$work/err")"; then
    fail "zero exit status when a file cannot be read"
  else
    pass "nonzero exit status when a file cannot be read"
  fi
  check_output "omits unreadable files from the output" "$work/a.txt" "$out"
  # Look for `uniq-contents`'s own message, not merely for the file name:
  # the shell's "cannot open" message for the failed input redirection also
  # names the file, so a laxer test would pass even without the fix.
  for f in "$work/c.txt" "$work/d.txt"; do
    if grep -qF -- "uniq-contents: cannot read $f" "$work/err"; then
      pass "reported $(basename -- "$f") on stderr"
    else
      fail "did not report $(basename -- "$f") on stderr"
      cat "$work/err"
    fi
  done

  # An unreadable file must not make a later readable file look like a
  # duplicate of it.
  out="$("$UNIQ" "$work/c.txt" "$work/b.txt" 2> /dev/null || true)"
  check_output "an unreadable file does not mask a later readable one" \
    "$work/b.txt" "$out"
fi

### A nonexistent file is an error, and a directory is a warning; neither is
### silently skipped.

if out="$("$UNIQ" "$work/nosuch.txt" "$work/a.txt" 2> "$work/err")"; then
  fail "zero exit status for a nonexistent file"
else
  pass "nonzero exit status for a nonexistent file"
fi
check_output "omits a nonexistent file from the output" "$work/a.txt" "$out"
if grep -qF -- "uniq-contents: no such file: $work/nosuch.txt" "$work/err"; then
  pass "reported a nonexistent file on stderr"
else
  fail "did not report a nonexistent file on stderr"
  cat "$work/err"
fi

# A directory is only a warning:  `uniq-contents *` in a directory that
# contains a subdirectory must not abort a caller that uses `set -e`.
mkdir "$work/adir"
if out="$("$UNIQ" "$work/adir" "$work/a.txt" 2> "$work/err")"; then
  pass "zero exit status for a directory"
else
  fail "nonzero exit status for a directory"
fi
check_output "omits a directory from the output" "$work/a.txt" "$out"
if grep -qF -- "uniq-contents: warning: not a regular file: $work/adir" "$work/err"; then
  pass "reported a directory on stderr"
else
  fail "did not report a directory on stderr"
  cat "$work/err"
fi

# A directory does not mask a read error elsewhere in the argument list.
if [ "$(id -u)" != 0 ]; then
  if "$UNIQ" "$work/adir" "$work/c.txt" 2> /dev/null; then
    fail "zero exit status for an unreadable file alongside a directory"
  else
    pass "nonzero exit status for an unreadable file alongside a directory"
  fi
fi

### A file name containing a backslash is printed and reported literally.
### The escape sequence matters:  some shells' `echo` (dash's, for one) turns
### the two characters `\t` into a tab, so a diagnostic that used `echo` would
### name a file that does not exist.

esc='tab\there.txt'
printf 'eee\n' > "$work/$esc"
out="$("$UNIQ" "$work/$esc")"
check_output "prints a file name containing a backslash escape literally" \
  "$work/$esc" "$out"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$work/$esc"
  "$UNIQ" "$work/$esc" 2> "$work/err" || true
  if grep -qF -- "uniq-contents: cannot read $work/$esc" "$work/err"; then
    pass "reported a file name containing a backslash escape literally"
  else
    fail "did not report a file name containing a backslash escape literally"
    cat "$work/err"
  fi
fi

exit "$status"
