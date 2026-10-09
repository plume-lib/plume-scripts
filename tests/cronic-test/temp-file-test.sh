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
# while `cronic` is running the command rather than before or after.
cat > "$work/wait-for-release" << 'EOF'
#!/bin/sh
touch "$1"
while [ ! -e "$2" ]; do
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

### The temporary file names are not derived from the process id.

# A temporary file name built from `$$` would be predictable.  `$$` is
# `cronic`'s process id even within its subshells, so `cronic`'s process id is
# the only one to check.  While the wrapped command runs, look for that id in
# the names under the $TMPDIR that this test sets, and for the predictable names
# under /tmp.  The test fails if `cronic` has no temporary files at that time,
# so that it cannot pass vacuously.
"$CRONIC" "$work/wait-for-release" "$work/started-1" "$work/release-1" \
  > "$work/output" 2>&1 &
cronic_pid=$!
wait_for_start "$work/started-1"
during="$(temp_files)"
predictable="$(
  find "$TMPDIR" -name "*$cronic_pid*"
  for file in "/tmp/cronic.out.$cronic_pid" "/tmp/cronic.err.$cronic_pid" \
    "/tmp/cronic.err.reduced.$cronic_pid" "/tmp/cronic.trace.$cronic_pid"; do
    if [ -e "$file" ]; then
      echo "$file"
    fi
  done
)"
touch "$work/release-1"
wait "$cronic_pid" || fail "nonzero exit status: $(cat "$work/output")"
if [ -z "$during" ]; then
  fail "cronic had no temporary files while the wrapped command ran"
elif [ -n "$predictable" ]; then
  fail "temporary file names are predictable from the process id:"
  echo "$predictable"
else
  pass "temporary file names are not predictable from the process id"
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
