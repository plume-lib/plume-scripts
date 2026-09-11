#!/bin/sh

# Tests `classfile_check_version`:  it exits 0 if a .class file's version is
# <= the given version, and nonzero otherwise.
#
# Only the first 8 bytes of a .class file matter to the script -- the magic
# number 0xcafebabe, the minor version, and the major version -- so the test
# inputs are 8-byte files rather than real compiled classes.
#
# `classfile_check_version` is a csh script, so this test does nothing if csh
# is not installed.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
CCV="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/classfile_check_version"

# The script's shebang is "#! /bin/csh -f", so csh must be at that exact path
# and not merely somewhere on PATH.
if [ ! -x /bin/csh ]; then
  echo "SKIP: classfile_check_version tests: /bin/csh does not exist"
  exit 0
fi
for prerequisite in xxd bc; do
  if ! command -v "$prerequisite" > /dev/null 2>&1; then
    echo "SKIP: classfile_check_version tests: $prerequisite is not installed"
    exit 0
  fi
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

# check DESCRIPTION EXPECTED-STATUS ARG...: runs `classfile_check_version` and
# checks its exit status.
check() {
  description="$1"
  expected_status="$2"
  shift 2
  actual_status=0
  "$CCV" "$@" > "$work/output" 2>&1 || actual_status=$?
  if [ "$actual_status" = "$expected_status" ]; then
    echo "PASS: $description"
  else
    echo "FAIL: $description: exit status $actual_status, expected $expected_status"
    cat "$work/output"
    status=1
  fi
}

# check_output DESCRIPTION PATTERN: checks the output of the preceding `check`.
check_output() {
  case "$(cat "$work/output")" in
    *"$2"*)
      echo "PASS: $1"
      ;;
    *)
      echo "FAIL: $1: output does not contain '$2':"
      cat "$work/output"
      status=1
      ;;
  esac
}

# `exit -1` in csh yields exit status 255.
FAILURE_STATUS=255

# An 8-byte .class file header:  the magic number 0xcafebabe, then the minor
# version 0, then the major version.  Major version 52 (octal 064) is Java 8
# and 49 (octal 061) is Java 5.
printf '\312\376\272\276\000\000\000\064' > "$work/Java8.class"
printf '\312\376\272\276\000\000\000\061' > "$work/Java5.class"

# A class file at exactly the limit is accepted.
check "version 52, limit 52" 0 52 "$work/Java8.class"

# A class file below the limit is accepted.
check "version 49, limit 52" 0 52 "$work/Java5.class"

# A class file above the limit is rejected, and its version is reported.
check "version 52, limit 49" "$FAILURE_STATUS" 49 "$work/Java8.class"
check_output "the too-new version is reported" "has version 52"

# A file that is not a class file is rejected.
printf 'not a class file at all\n' > "$work/notaclass.txt"
check "not a class file" "$FAILURE_STATUS" 52 "$work/notaclass.txt"
check_output "a non-class file is reported" "is not a Java class file"

# A nonexistent file is rejected.
check "nonexistent file" "$FAILURE_STATUS" 52 "$work/nosuchfile.class"
check_output "a nonexistent file is reported" "does not exist"

# The wrong number of arguments is rejected.
check "no arguments" "$FAILURE_STATUS"
check_output "no arguments is reported" "two arguments"
check "one argument" "$FAILURE_STATUS" 52
check_output "one argument is reported" "two arguments"
check "three arguments" "$FAILURE_STATUS" 52 "$work/Java8.class" extra
check_output "three arguments is reported" "two arguments"

exit "$status"
