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

# Don't let the user's environment file run in `cronic` or in the bash commands
# below.  It could write to stderr, especially when an exported SHELLOPTS turns
# on `-u` for it.
unset BASH_ENV

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
CRONIC="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/cronic"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Give `cronic` a temporary directory of its own, so that the checks below see
# only the runs that this test starts, and not a concurrent `cronic` run
# started by another test or by another user of the machine.
TMPDIR="$work/tmp"
export TMPDIR
mkdir "$TMPDIR"

status=0

# A command whose stderr is nothing but trace lines.
cat > "$work/trace-only" << 'EOF'
#!/bin/bash
set -x
echo "the standard output"
exit "$1"
EOF
chmod +x "$work/trace-only"

# A command that writes real error output in addition to trace lines.
cat > "$work/trace-and-stderr" << 'EOF'
#!/bin/bash
set -x
echo "a real error" 1>&2
exit "$1"
EOF
chmod +x "$work/trace-and-stderr"

# A command whose stderr is nothing but `make` directory-change notices.  Both
# the top-level form (`make:`) and the recursive form (`make[1]:`) appear; both
# must be filtered out of the reduced error output.
cat > "$work/make-noise" <<'EOF'
#!/bin/sh
echo "make: Entering directory '/tmp/x'" 1>&2
echo "make[1]: Entering directory '/tmp/x/sub'" 1>&2
echo "make[1]: Leaving directory '/tmp/x/sub'" 1>&2
echo "make: Leaving directory '/tmp/x'" 1>&2
exit "$1"
EOF
chmod +x "$work/make-noise"

# A command that writes a real error among the `make` directory-change notices.
cat > "$work/make-noise-and-stderr" <<'EOF'
#!/bin/sh
echo "make: Entering directory '/tmp/x'" 1>&2
echo "make[1]: Entering directory '/tmp/x/sub'" 1>&2
echo "a real error" 1>&2
echo "make[1]: Leaving directory '/tmp/x/sub'" 1>&2
echo "make: Leaving directory '/tmp/x'" 1>&2
exit "$1"
EOF
chmod +x "$work/make-noise-and-stderr"

# A bash command that reads an unset variable.
cat > "$work/read-unset" <<'EOF'
#!/bin/bash
unset CRONIC_TEST_UNSET_VARIABLE
echo "value: ${CRONIC_TEST_UNSET_VARIABLE}" > /dev/null
exit "$1"
EOF
chmod +x "$work/read-unset"

# A bash command in which a command fails before the script exits.
cat > "$work/ignore-failure" <<'EOF'
#!/bin/bash
false
exit "$1"
EOF
chmod +x "$work/ignore-failure"

# Runs `cronic` with SHELLOPTS set to its first argument and exported.
cat > "$work/cronic-with-shellopts" <<'EOF'
#!/bin/sh
shellopts="$1"
shift
SHELLOPTS="$shellopts" exec "$REAL_CRONIC" "$@"
EOF
chmod +x "$work/cronic-with-shellopts"

# temp_files: prints `cronic`'s temporary files, in a canonical order.
temp_files() {
  find "$TMPDIR" -mindepth 1 -maxdepth 1 2> /dev/null | sort
}

# check DESCRIPTION EXPECTED-STATUS EXPECTED-OUTPUT COMMAND...: runs `cronic`
# on COMMAND and checks its exit status, whether it printed a report, and that
# it left no temporary files behind.  EXPECTED-OUTPUT is "silent", "report",
# "report:TEXT", which also requires TEXT to appear in the report, or
# "message:TEXT", which requires TEXT to appear in output that need not be a
# report.
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
  elif [ "${expected_output#message:}" = "$expected_output" ]; then
    if ! grep -q "^END OF CRONIC OUTPUT.$" "$work/output"; then
      echo "FAIL: $description: expected a report, but got:"
      cat "$work/output"
      status=1
      return
    fi
  fi
  case "$expected_output" in
    report:* | message:*)
      if ! grep -q "${expected_output#*:}" "$work/output"; then
        echo "FAIL: $description: expected the output to contain" \
          "\"${expected_output#*:}\", but got:"
        cat "$work/output"
        status=1
        return
      fi
      ;;
  esac

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

# `make` directory-change notices are not error output, whether they come from
# a top-level `make` or from a recursive one.
check "make directory-change notices, exit 0" 0 silent "$work/make-noise" 0

# ... but a real error among them is still reported.
check "make directory-change notices and real stderr, exit 0" 0 \
  "report:^a real error$" "$work/make-noise-and-stderr" 0

# Without a command, `cronic` reports a usage error rather than aborting on an
# unset variable.
check "no arguments" 2 "message:^Usage: "
check "--expected-status without a value" 2 "message:^Usage: " \
  --expected-status
check "--permit-stderr without a command" 2 "message:^Usage: " \
  --permit-stderr

# When SHELLOPTS is exported, `cronic`'s own `-e` and `-u` options do not reach
# the wrapped command, but the caller's options do.
REAL_CRONIC="$CRONIC"
export REAL_CRONIC
CRONIC="$work/cronic-with-shellopts"
default_shellopts=braceexpand:hashall:interactive-comments
check "exported SHELLOPTS, command reads an unset variable" 0 silent \
  "$default_shellopts" "$work/read-unset" 0
check "exported SHELLOPTS, command ignores a failure" 0 silent \
  "$default_shellopts" "$work/ignore-failure" 0
check "exported SHELLOPTS with nounset, command reads an unset variable" 1 \
  "report:unbound variable" \
  "$default_shellopts:nounset" "$work/read-unset" 0
check "exported SHELLOPTS with errexit, command ignores a failure" 1 report \
  "$default_shellopts:errexit" "$work/ignore-failure" 0
CRONIC="$REAL_CRONIC"

exit "$status"
