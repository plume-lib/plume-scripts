#!/bin/sh

# Tests `cronic`, concentrating on the case where the wrapped command's stderr
# consists only of `PS4` execution-trace lines, as when the command runs under
# `set -x` and writes no other error output.
#
# `cronic` filters trace lines out of stderr with `grep -v`, which exits with
# status 1 when it selects no lines.  `cronic` runs under `set -e`, so an
# unguarded `grep -v` aborted the script at that point:  no report was printed,
# the exit status was grep's 1 rather than the wrapped command's, and all of
# the temporary files under /tmp were left behind.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
CRONIC="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/cronic"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

# A command whose stderr is nothing but trace lines.
cat > "$work/trace-only" <<'EOF'
#!/bin/bash
set -x
echo "the standard output"
exit "$1"
EOF
chmod +x "$work/trace-only"

# A command that writes real error output in addition to trace lines.
cat > "$work/trace-and-stderr" <<'EOF'
#!/bin/bash
set -x
echo "a real error" 1>&2
exit "$1"
EOF
chmod +x "$work/trace-and-stderr"

# temp_files: prints `cronic`'s temporary files, in a canonical order.
temp_files() {
  find /tmp -maxdepth 1 -name 'cronic.*' 2> /dev/null | sort
}

# check DESCRIPTION EXPECTED-STATUS EXPECTED-OUTPUT COMMAND...: runs `cronic`
# on COMMAND and checks its exit status, whether it printed a report, and that
# it left no temporary files behind.  EXPECTED-OUTPUT is "report" or "silent".
check() {
  description="$1"
  expected_status="$2"
  expected_output="$3"
  shift 3

  before="$(temp_files)"
  actual_status=0
  "$CRONIC" "$@" > "$work/output" 2>&1 || actual_status=$?
  after="$(temp_files)"

  if [ "$actual_status" != "$expected_status" ]; then
    echo "FAIL: $description: exit status $actual_status, expected $expected_status"
    cat "$work/output"
    status=1
    return
  fi

  if [ "$expected_output" = "silent" ]; then
    if [ -s "$work/output" ]; then
      echo "FAIL: $description: expected no output, but got:"
      cat "$work/output"
      status=1
      return
    fi
  else
    if ! grep -q "^END OF CRONIC OUTPUT.$" "$work/output"; then
      echo "FAIL: $description: expected a report, but got:"
      cat "$work/output"
      status=1
      return
    fi
  fi

  if [ "$before" != "$after" ]; then
    echo "FAIL: $description: temporary files were left behind:"
    echo "$after"
    status=1
    return
  fi

  echo "PASS: $description"
}

# Trace-only stderr and a successful command:  nothing to report.
check "trace-only stderr, exit 0" 0 silent "$work/trace-only" 0

# Trace-only stderr and a failing command:  the failure is reported, and
# `cronic` exits with the command's status.
check "trace-only stderr, exit 3" 3 report "$work/trace-only" 3

# Trace-only stderr and a failing command whose status is expected.
check "trace-only stderr, expected nonzero status" 3 silent \
  --expected-status 3 "$work/trace-only" 3

# Real error output among the trace lines is reported, even on success.
check "trace lines and real stderr, exit 0" 0 report "$work/trace-and-stderr" 0

# ... unless --permit-stderr says not to.
check "trace lines and real stderr, --permit-stderr" 0 silent \
  --permit-stderr "$work/trace-and-stderr" 0

exit "$status"
