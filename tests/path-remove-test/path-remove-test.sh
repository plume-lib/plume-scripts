#!/bin/sh

# Tests `path-remove`:  it shortens a path environment variable by removing
# duplicate and non-existent directories, and optionally those matching a
# regular expression.
#
# Not tested here, because it is currently broken:  input that mixes
# colon-separated and space-separated lines, which is joined with whichever
# separator the last line used.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PATH_REMOVE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/path-remove"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

# check_equal DESCRIPTION EXPECTED ACTUAL: reports whether two strings match.
check_equal() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    echo "  expected: <<$2>>"
    echo "  actual:   <<$3>>"
    status=1
  fi
}

mkdir "$work/a" "$work/b" "$work/c"
touch "$work/regular-file"

# Duplicates and non-existent directories are removed, and the order of the
# surviving elements is unchanged.
actual="$(echo "$work/a:$work/nonexistent:$work/b:$work/a" | "$PATH_REMOVE")"
check_equal "colon-separated: duplicates and non-existent" "$work/a:$work/b" "$actual"

# A space-separated path stays space-separated.
actual="$(echo "$work/a $work/b $work/a" | "$PATH_REMOVE")"
check_equal "space-separated path" "$work/a $work/b" "$actual"

# A path element that is a file, not a directory, is removed.
actual="$(echo "$work/a:$work/regular-file:$work/b" | "$PATH_REMOVE")"
check_equal "a non-directory is removed" "$work/a:$work/b" "$actual"

# "-r REGEXP" removes every matching element.
actual="$(echo "$work/a:$work/b:$work/c" | "$PATH_REMOVE" -r 'b$')"
check_equal "-r removes matching elements" "$work/a:$work/c" "$actual"

# A single element, with no separator in the input, is passed through.
actual="$(echo "$work/a" | "$PATH_REMOVE")"
check_equal "single element" "$work/a" "$actual"

# If nothing survives, the output is empty rather than a stray separator.
actual="$(echo "$work/nonexistent1:$work/nonexistent2" | "$PATH_REMOVE")"
check_equal "nothing survives" "" "$actual"

# "-r" without a regexp is an error.
actual_status=0
echo "$work/a" | "$PATH_REMOVE" -r > /dev/null 2>&1 || actual_status=$?
if [ "$actual_status" = 0 ]; then
  echo "FAIL: -r without an argument should fail"
  status=1
else
  echo "PASS: -r without an argument fails"
fi

# An unrecognized argument is an error.
actual_status=0
echo "$work/a" | "$PATH_REMOVE" -x > /dev/null 2>&1 || actual_status=$?
if [ "$actual_status" = 0 ]; then
  echo "FAIL: an unrecognized argument should fail"
  status=1
else
  echo "PASS: an unrecognized argument fails"
fi

exit "$status"
