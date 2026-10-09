#!/bin/sh

# Tests how `cronic` creates and removes its temporary files.
#
# Temporary file names built from the process id, such as `/tmp/cronic.out.$$`,
# would be unsafe:  process ids are guessable and reused, so on a multi-user
# machine another user could pre-create those paths as symlinks and have the
# wrapped command's output written through them.  Without a signal handler, a
# run that was interrupted before its final cleanup would leave its temporary
# files behind.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
CRONIC="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/cronic"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Give `cronic` a temporary directory of its own, so that the checks below see
# only the runs that this test starts.  Scanning the shared /tmp instead would
# make this test fail whenever any other `cronic` run on the machine -- another
# test running under `make -j`, or an unrelated user's cron job -- happened to
# hold a temporary directory between a "before" and an "after" snapshot.
TMPDIR="$work/tmp"
export TMPDIR
mkdir "$TMPDIR"

status=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  status=1
}

# temp_files: prints `cronic`'s temporary files, in a canonical order.
temp_files() {
  find "$TMPDIR" -mindepth 1 -maxdepth 1 2> /dev/null | sort
}

# Waits for the test to create the "release" file, so that the test can act
# while `cronic` is running the command rather than before or after.  If a third
# argument is given, writes it to stdout and stderr first, so that the test can
# find the files that `cronic` redirected them to.  Gives up if the release
# file's directory disappears, as it does when the test exits early; otherwise
# this script and `cronic` would never terminate.
cat > "$work/wait-for-release" << 'EOF'
#!/bin/sh
if [ $# -ge 3 ]; then
  echo "$3"
  echo "$3" >&2
fi
touch "$1"
while [ ! -e "$2" ] && [ -d "$(dirname -- "$2")" ]; do
  sleep 0.1
done
EOF
chmod +x "$work/wait-for-release"

# wait_for_start FILE: waits until the wrapped command has created FILE.
wait_for_start() {
  waited=0
  while [ ! -e "$1" ]; do
    if [ "$waited" -ge 100 ]; then
      echo "the wrapped command did not start"
      exit 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
}

### The temporary files are in a private directory with an unpredictable name.

# A temporary file name built from `$$`, `$RANDOM`, the time, or the like would
# be predictable.  Rather than guess how a name might be predictable, check
# where the wrapped command's output actually goes:  the command writes a
# string that is unique to this test run, and the test looks for the files that
# contain it.  Each such file must be directly within a directory that `mktemp
# -d` created in $TMPDIR:  named `cronic.XXXXXX` and accessible only by its
# owner.  Searching /tmp as well catches a `cronic` that ignores $TMPDIR.  The
# test also fails if it finds no such files, so that it cannot pass vacuously.
marker="cronic temp-file-test marker $work"

# marker_files: prints the files that contain the marker.  Files directly
# within /tmp, or within a subdirectory of it, are searched, except for this
# test's own files.  Errors, such as unreadable files, are ignored.
marker_files() {
  {
    find "$TMPDIR" -type f -exec grep -lF -- "$marker" {} + 2> /dev/null || true
    find /tmp -maxdepth 2 -path "$work" -prune \
      -o -type f -user "$(id -u)" -exec grep -lF -- "$marker" {} + \
      2> /dev/null || true
  } | sort -u
}

# in_private_dir FILE: succeeds if FILE is directly within a directory in
# $TMPDIR that is named like `mktemp`'s `cronic.XXXXXX` template and that is
# accessible only by its owner.
in_private_dir() {
  dir="$(dirname -- "$1")"
  [ "$(dirname -- "$dir")" = "$TMPDIR" ] || return 1
  case "$(basename -- "$dir")" in
    cronic.??????) ;;
    *) return 1 ;;
  esac
  [ -n "$(find "$dir" -prune -perm 700)" ]
}

"$CRONIC" "$work/wait-for-release" "$work/started-1" "$work/release-1" \
  "$marker" > "$work/output" 2>&1 &
cronic_pid=$!
wait_for_start "$work/started-1"
found="$(marker_files)"
unsafe=""
while IFS= read -r file; do
  if [ -n "$file" ] && ! in_private_dir "$file"; then
    unsafe="$unsafe$file
"
  fi
done << EOF
$found
EOF
touch "$work/release-1"
wait "$cronic_pid" || fail "nonzero exit status: $(cat "$work/output")"
if [ -n "$unsafe" ]; then
  fail "temporary files are not in a private directory created by mktemp:"
  printf '%s' "$unsafe"
fi
if [ -z "$found" ]; then
  fail "found no temporary files of cronic while the wrapped command ran"
fi
if [ -n "$found" ] && [ -z "$unsafe" ]; then
  pass "temporary files are in a private directory created by mktemp"
fi

### An interrupted run leaves no temporary files behind.

before="$(temp_files)"
"$CRONIC" "$work/wait-for-release" "$work/started-2" "$work/release-2" \
  > "$work/output" 2>&1 &
cronic_pid=$!
wait_for_start "$work/started-2"

# `cronic` is waiting for the wrapped command, so it handles the signal only
# once that command has finished; release the command after signaling.
kill -TERM "$cronic_pid"
touch "$work/release-2"
cronic_status=0
# Redirect stderr to discard the shell's "Terminated" job message, which would
# otherwise look like a failure in the test output.
wait "$cronic_pid" 2> /dev/null || cronic_status=$?

# Without this check, a `cronic` that ignored the signal and ran to completion
# would also leave no temporary files behind, and so would pass the check below.
# The shell reports death by signal N as status 128+N, so SIGTERM is 143.
if [ "$cronic_status" -ne 143 ]; then
  fail "the run was not interrupted: exit status $cronic_status, expected 143"
  cat "$work/output"
else
  pass "an interrupted run exits with the status of the signal that killed it"
fi

after="$(temp_files)"
if [ "$before" != "$after" ]; then
  fail "an interrupted run left temporary files behind:"
  echo "$after"
else
  pass "an interrupted run left no temporary files behind"
fi

exit "$status"
