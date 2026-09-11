#!/bin/sh

# Tests for `path-remove`.
#
# The main point of this test is that the output separator is chosen once, for
# the whole output, rather than per input line.  `path-remove` merges all its
# input lines into a single path, so a colon-separated first line followed by a
# space-separated second line used to be emitted joined by spaces.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PATH_REMOVE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/path-remove"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

# `path-remove` drops directories that do not exist, so the test needs real
# ones.  A directory name never contains a space or a colon, so that neither
# separator can be confused for part of a name.
mkdir "$work/a" "$work/b" "$work/c"
a="$work/a"
b="$work/b"
c="$work/c"

status=0

# check DESCRIPTION EXPECTED INPUT [ARG...]:  runs `path-remove ARG...` on
# INPUT and checks that its output is EXPECTED.
check() {
  description="$1"
  expected="$2"
  input="$3"
  shift 3
  actual="$(printf '%s' "$input" | "$PATH_REMOVE" "$@")"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $description"
  else
    echo "FAIL: $description"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    status=1
  fi
}

### The separator is the same for the whole output, not per input line.

check "colon line before space line" \
  "$a:$b:$c" \
  "$a:$b
$c $a"
check "space line before colon line" \
  "$a $b $c" \
  "$a $b
$c:$a"

### A separatorless line does not determine the separator.

check "separatorless line before space line" \
  "$a $b $c" \
  "$a
$b $c"

### Single-line inputs keep their own separator.

check "colon-separated input" "$a:$b" "$a:$b"
check "space-separated input" "$a $b" "$a $b"
check "separatorless input" "$a" "$a"

### The other documented behaviors still hold.

check "removes duplicates" "$a:$b" "$a:$b:$a"
check "removes nonexistent directories" "$a:$b" "$a:$work/nosuch:$b"
check "-r removes matching elements" "$a:$c" "$a:$b:$c" -r "/b\$"

exit "$status"
