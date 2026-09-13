#!/bin/sh

# Tests `preplace`:  timestamp-preserving regular expression replacement over
# a file, a directory, or (by default) everything under the current directory.
#
# The central promise of `preplace` is that a file's timestamp is updated only
# when the replacement actually changes that file, so the timestamp checks
# below are as important as the content checks.
#
# Two behaviors have tests of their own in this directory:  binary-test.sh
# checks that binary files are not rewritten, and symlink-test.sh checks that
# a symbolic link is not replaced by a regular file.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PREPLACE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/preplace"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

# An old timestamp to set on files before running `preplace`, so that "the
# timestamp was updated" is unambiguous.
OLD_TIMESTAMP=202001010000

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

# mtime FILE: prints FILE's modification time, in seconds since the epoch.
# Uses Perl (which `preplace` requires anyway) because `stat`'s command-line
# interface differs between GNU and BSD.
mtime() {
  perl -e 'print((stat($ARGV[0]))[9])' "$1"
}

# check_unmodified DESCRIPTION FILE: checks that FILE still has OLD_TIMESTAMP.
check_unmodified() {
  if [ "$(mtime "$2")" = "$(mtime "$work/reference")" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1: the timestamp of $2 was updated"
    status=1
  fi
}

# check_modified DESCRIPTION FILE: checks that FILE's timestamp was updated.
check_modified() {
  if [ "$(mtime "$2")" = "$(mtime "$work/reference")" ]; then
    echo "FAIL: $1: the timestamp of $2 was not updated"
    status=1
  else
    echo "PASS: $1"
  fi
}

touch -t "$OLD_TIMESTAMP" "$work/reference"

## Replacement over the current directory, which is the default.

recursive="$work/recursive"
mkdir -p "$recursive/sub"
echo "hello world" > "$recursive/f1.txt"
echo "nothing here" > "$recursive/f2.txt"
echo "hello again" > "$recursive/sub/f3.txt"
touch -t "$OLD_TIMESTAMP" "$recursive/f1.txt" "$recursive/f2.txt" \
  "$recursive/sub/f3.txt"

(cd "$recursive" && "$PREPLACE" hello HOWDY)

check_equal "replacement in the current directory" "HOWDY world" "$(cat "$recursive/f1.txt")"
check_equal "replacement in a subdirectory" "HOWDY again" "$(cat "$recursive/sub/f3.txt")"
check_equal "a non-matching file is unchanged" "nothing here" "$(cat "$recursive/f2.txt")"
check_modified "a matching file's timestamp is updated" "$recursive/f1.txt"
check_unmodified "a non-matching file's timestamp is preserved" "$recursive/f2.txt"

## -preserve

echo "keep me" > "$work/keep.txt"
touch -t "$OLD_TIMESTAMP" "$work/keep.txt"
"$PREPLACE" -preserve keep KEPT "$work/keep.txt"
check_equal "-preserve still replaces" "KEPT me" "$(cat "$work/keep.txt")"
check_unmodified "-preserve keeps the old timestamp" "$work/keep.txt"

## -name

named="$work/named"
mkdir "$named"
echo "hello txt" > "$named/only.txt"
echo "hello md" > "$named/only.md"
(cd "$named" && "$PREPLACE" -name '\.md$' hello BYE)
check_equal "-name selects a file" "BYE md" "$(cat "$named/only.md")"
check_equal "-name excludes a file" "hello txt" "$(cat "$named/only.txt")"

## Explicit file arguments

echo "aaa" > "$work/explicit.txt"
"$PREPLACE" aaa bbb "$work/explicit.txt"
check_equal "an explicitly named file" "bbb" "$(cat "$work/explicit.txt")"

# A file named on the command line is used even if `-name` would exclude it.
echo "aaa" > "$work/explicit2.txt"
"$PREPLACE" -name '\.md$' aaa bbb "$work/explicit2.txt"
check_equal "-name does not apply to explicit arguments" "bbb" "$(cat "$work/explicit2.txt")"

## -i.bak

echo "zzz" > "$work/backup.txt"
"$PREPLACE" -i.bak zzz yyy "$work/backup.txt"
check_equal "-i.bak replaces" "yyy" "$(cat "$work/backup.txt")"
check_equal "-i.bak makes a backup" "zzz" "$(cat "$work/backup.txt.bak")"

## A regex containing a slash, which forces a different substitution delimiter.

echo "a/b/c" > "$work/slash.txt"
"$PREPLACE" 'a/b' 'x/y' "$work/slash.txt"
check_equal "a regex containing a slash" "x/y/c" "$(cat "$work/slash.txt")"

## Exit status

# An argument that is neither a file nor a directory is an error, so that a
# Makefile or pipeline does not silently ignore the typo.
actual_status=0
"$PREPLACE" aaa bbb "$work/nosuchfile.txt" > /dev/null 2>&1 || actual_status=$?
check_equal "a nonexistent argument exits nonzero" "1" "$actual_status"

# Too few arguments is an error.
actual_status=0
"$PREPLACE" onlyonearg > /dev/null 2>&1 || actual_status=$?
if [ "$actual_status" = 0 ]; then
  echo "FAIL: too few arguments should fail"
  status=1
else
  echo "PASS: too few arguments fails"
fi

# -help succeeds and prints a usage message.
actual_status=0
help_output="$("$PREPLACE" -help 2>&1)" || actual_status=$?
check_equal "-help exits 0" "0" "$actual_status"
case "$help_output" in
  *"preplace [options] oldregex newreplacement [files]"*)
    echo "PASS: -help prints usage"
    ;;
  *)
    echo "FAIL: -help does not print usage; got: $help_output"
    status=1
    ;;
esac

exit "$status"
