#!/bin/sh

# Tests how `cronic` creates and removes its temporary files.
#
# `cronic` used to write to `/tmp/cronic.out.$$` and three sibling paths.
# Process ids are guessable and reused, so on a multi-user machine another user
# could pre-create those paths as symlinks and have the wrapped command's
# output written through them.  `cronic` also had no signal handler, so a run
# that was interrupted before its final `rm` left all four files behind.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
CRONIC="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/cronic"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

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
  find "${TMPDIR:-/tmp}" /tmp -maxdepth 1 -name 'cronic.*' 2> /dev/null | sort -u
}

### The temporary file names are not derived from the process id.

# The wrapped command's parent is `cronic` itself, so $PPID is the process id
# that the old names were built from.
cat > "$work/report-ppid" << 'EOF'
#!/bin/sh
for file in "/tmp/cronic.out.$PPID" "/tmp/cronic.err.$PPID" \
  "/tmp/cronic.err.reduced.$PPID" "/tmp/cronic.trace.$PPID"; do
  if [ -e "$file" ]; then
    echo "$file" >> "$1"
  fi
done
EOF
chmod +x "$work/report-ppid"

"$CRONIC" "$work/report-ppid" "$work/predictable" > "$work/output" 2>&1 \
  || fail "nonzero exit status: $(cat "$work/output")"
if [ -e "$work/predictable" ]; then
  fail "temporary file names are predictable from the process id:"
  cat "$work/predictable"
else
  pass "temporary file names are not predictable from the process id"
fi

### An interrupted run leaves no temporary files behind.

# Waits for the test to create the "release" file, so that the signal arrives
# while `cronic` is running the command rather than before or after.
cat > "$work/wait-for-release" << 'EOF'
#!/bin/sh
touch "$1"
while [ ! -e "$2" ]; do
  sleep 0.1
done
EOF
chmod +x "$work/wait-for-release"

before="$(temp_files)"
"$CRONIC" "$work/wait-for-release" "$work/started" "$work/release" \
  > "$work/output" 2>&1 &
cronic_pid=$!

waited=0
while [ ! -e "$work/started" ]; do
  if [ "$waited" -ge 100 ]; then
    echo "the wrapped command did not start"
    exit 1
  fi
  sleep 0.1
  waited=$((waited + 1))
done

# `cronic` is waiting for the wrapped command, so it handles the signal only
# once that command has finished; release the command after signaling.
kill -TERM "$cronic_pid"
touch "$work/release"
wait "$cronic_pid" || true

after="$(temp_files)"
if [ "$before" != "$after" ]; then
  fail "an interrupted run left temporary files behind:"
  echo "$after"
else
  pass "an interrupted run left no temporary files behind"
fi

exit "$status"
