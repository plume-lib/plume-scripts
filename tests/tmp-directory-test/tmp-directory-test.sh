#!/bin/sh

# Tests that no script uses or recommends `/tmp/plume-scripts`, a directory
# whose name is the same for every user of the machine.
#
# On a multi-user or shared CI host, whoever creates `/tmp/plume-scripts` first
# owns it, and every other user then sources and executes whatever it contains.
# The README installs into `/tmp/$USER/plume-scripts` for that reason; the
# "Typical use" comments in the scripts, and `set-git-range`'s default for
# PLUME_SCRIPTS, must not tell a different story.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

status=0

# no_shared_tmp FILE: fails if FILE mentions a /tmp directory that is not
# per-user.  `/tmp/$USER/plume-scripts` does not match either pattern.
no_shared_tmp() {
  file="$1"
  matches="$(grep -n -e '/tmp/plume-scripts' -e '/tmp \+&&' -e 'git -C /tmp ' \
    "${PLUME_SCRIPTS}/$file" || true)"
  if [ -n "$matches" ]; then
    echo "FAIL: $file names a /tmp directory that is not per-user:"
    echo "$matches" | sed 's/^/  /'
    status=1
  else
    echo "PASS: $file names only per-user /tmp directories"
  fi
}

for file in README.md ci-info ci-org-and-branch git-changes \
  set-ci-org-and-branch set-git-range; do
  no_shared_tmp "$file"
done

# The default for PLUME_SCRIPTS is only visible in the message that
# `set-git-range` prints when it cannot find `set-ci-org-and-branch` there, so
# check that message.  A client that installed where the README says, and that
# did not set PLUME_SCRIPTS, must be looked for in its own directory.
#
# Run with an empty environment except for a made-up USER, both so that a CI
# variable of this test's own cannot send the script down another code path and
# so that the directory in the message is one that does not exist.
check_default() {
  description="$1"
  expected="$2"
  shift 2
  # shellcheck disable=SC2016
  actual="$(env -i PATH="$PATH" HOME="$HOME" "$@" sh -c '
    . "$1"/set-git-range
  ' sh "$PLUME_SCRIPTS" 2>&1 || true)"
  case "$actual" in
    *"$expected"*)
      echo "PASS: $description: looks in $expected"
      ;;
    *)
      echo "FAIL: $description: does not look in $expected"
      echo "  output: $actual"
      status=1
      ;;
  esac
}

check_default "set-git-range with USER set" \
  "/tmp/plume-scripts-test-user/plume-scripts/set-ci-org-and-branch" \
  USER=plume-scripts-test-user
# With USER unset -- as under cron and under some CI runners -- the default must
# still be per-user, and in particular must not collapse to `/tmp/plume-scripts`.
check_default "set-git-range with USER unset" \
  "/tmp/$(id -un)/plume-scripts/set-ci-org-and-branch"

exit "$status"
