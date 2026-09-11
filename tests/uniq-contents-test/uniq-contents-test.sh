#!/bin/sh

# Tests `uniq-contents`:  given file names as arguments, it prints the ones
# with unique contents, keeping the first file of each group of files with
# identical contents.
#
# Not tested here, because it is currently broken:  an unreadable file is
# silently dropped, and two unreadable files are declared identical, because
# the exit status of the hashing command is not checked.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
UNIQ_CONTENTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/uniq-contents"

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

printf 'aaa\n' > "$work/a.txt"
printf 'bbb\n' > "$work/b.txt"
printf 'aaa\n' > "$work/c.txt"
printf 'ccc\n' > "$work/d.txt"
: > "$work/empty1.txt"
: > "$work/empty2.txt"
mkdir "$work/adir"

cd "$work"

# The first file of each duplicate group is printed, and the later ones are not.
actual="$("$UNIQ_CONTENTS" a.txt b.txt c.txt d.txt)"
check_equal "duplicates are dropped" "a.txt
b.txt
d.txt" "$actual"

# "First" means first in argument order, not alphabetical order.
actual="$("$UNIQ_CONTENTS" c.txt a.txt)"
check_equal "argument order determines the survivor" "c.txt" "$actual"

# Empty files are just another group of identical contents.
actual="$("$UNIQ_CONTENTS" empty1.txt empty2.txt)"
check_equal "empty files are duplicates of one another" "empty1.txt" "$actual"

# Arguments that are not regular files are skipped rather than reported.
actual="$("$UNIQ_CONTENTS" nosuchfile.txt adir a.txt)"
check_equal "non-files are skipped" "a.txt" "$actual"

# No arguments is not an error.
actual_status=0
actual="$("$UNIQ_CONTENTS")" || actual_status=$?
check_equal "no arguments produces no output" "" "$actual"
check_equal "no arguments exits 0" "0" "$actual_status"

# A file whose name contains a space is handled as one argument.
printf 'ddd\n' > "$work/has space.txt"
actual="$("$UNIQ_CONTENTS" "has space.txt" a.txt)"
check_equal "a name containing a space" "has space.txt
a.txt" "$actual"

exit "$status"
