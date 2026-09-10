#!/bin/sh

# Test that each test directory's generated files list, as a prerequisite, the
# script that produces them.  Without that prerequisite, `make test` reuses a
# stale generated file and passes even when the script under test is broken.

set -eu

cd "$(dirname "$0")"

status=0

# Usage: check DIRECTORY SCRIPT TARGET...
# Verifies that each TARGET in DIRECTORY is remade after SCRIPT is modified.
check() {
  dir="$1"
  script="$2"
  shift 2
  for target in "$@"; do
    # Bring the target up to date, so that only `script` is newer than it.
    if ! (cd "../$dir" && make --silent "$target" >/dev/null); then
      echo "FAILURE: cannot make $dir/$target"
      status=1
      continue
    fi
    touch "../../$script"
    # `make --question` exits 0 if the target is up to date, 1 if it is not.
    qstatus=0
    (cd "../$dir" && make --question "$target" >/dev/null 2>&1) || qstatus=$?
    if [ "$qstatus" -eq 0 ]; then
      echo "FAILURE: $dir/$target does not depend on $script"
      status=1
    elif [ "$qstatus" -ne 1 ]; then
      echo "FAILURE: \`make --question $target\` in $dir exited with status $qstatus"
      status=1
    fi
  done
}

check lint-diff-test lint-diff.py \
  words2-lint-pruned.txt reldir-lint-pruned.txt \
  guessstrip-lint-pruned.txt javaexception-lint-pruned.txt
check sort-compiler-output-test sort-compiler-output \
  errors1-sorted.actual errors2-sorted.actual
check sort-directory-order-test sort-directory-order \
  lines1.output
check squeeze-blank-lines-test squeeze-blank-lines \
  lines1.output lines1.output2 lines2.output blank.output

if [ "$status" -eq 0 ]; then
  echo "makefile-prereq-test: all tests passed"
fi
exit "$status"
