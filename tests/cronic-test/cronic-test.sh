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
cat > "$work/make-noise" << 'EOF'
#!/bin/sh
echo "make: Entering directory '/tmp/x'" 1>&2
echo "make[1]: Entering directory '/tmp/x/sub'" 1>&2
echo "make[1]: Leaving directory '/tmp/x/sub'" 1>&2
echo "make: Leaving directory '/tmp/x'" 1>&2
exit "$1"
EOF
chmod +x "$work/make-noise"

# A command that writes a real error among the `make` directory-change notices.
cat > "$work/make-noise-and-stderr" << 'EOF'
#!/bin/sh
echo "make: Entering directory '/tmp/x'" 1>&2
echo "make[1]: Entering directory '/tmp/x/sub'" 1>&2
echo "a real error" 1>&2
echo "make[1]: Leaving directory '/tmp/x/sub'" 1>&2
echo "make: Leaving directory '/tmp/x'" 1>&2
exit "$1"
EOF
chmod +x "$work/make-noise-and-stderr"

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

  case "$expected_output" in
    silent)
      if [ -s "$work/output" ]; then
        echo "FAIL: $description: expected no output, but got:"
        cat "$work/output"
        status=1
        return
      fi
      ;;
    report*)
      if ! grep -q "^END OF CRONIC OUTPUT.$" "$work/output"; then
        echo "FAIL: $description: expected a report, but got:"
        cat "$work/output"
        status=1
        return
      fi
      ;;
  esac
  case "$expected_output" in
    report:* | message:*)
      if ! grep -q -e "${expected_output#*:}" "$work/output"; then
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
check "no arguments" 64 "message:^Usage: "
check "--expected-status without a value" 64 \
  "message:--expected-status requires a value" \
  --expected-status
check "--permit-stderr without a command" 64 "message:^Usage: " \
  --permit-stderr

# A non-integer expected status is a usage error, rather than a value that
# makes every exit status look expected.
check "--expected-status with a non-integer value" 64 \
  "message:requires an integer from 0 to 255" \
  --expected-status x "$work/trace-only" 1
# So is a value that no exit status can equal, or that the shell's integer
# comparisons cannot handle.
check "--expected-status larger than 255" 64 \
  "message:requires an integer from 0 to 255" \
  --expected-status 256 "$work/trace-only" 1
check "--expected-status too large for an integer comparison" 64 \
  "message:requires an integer from 0 to 255" \
  --expected-status 99999999999999999999 "$work/trace-only" 1
check "--expected-status with a leading zero" 64 \
  "message:requires an integer from 0 to 255" \
  --expected-status 09 "$work/trace-only" 1

# The options may be given in any order.
check "options out of order" 3 silent \
  --permit-stderr --expected-status 3 "$work/trace-and-stderr" 3
# An unknown option is a usage error, rather than a command to run.
check "unknown option" 64 "message:unknown option" \
  --no-such-option "$work/trace-only" 0
check "unknown single-dash option" 64 "message:unknown option" \
  -v "$work/trace-only" 0
# The value of `--expected-status` may follow an equals sign.
check "--expected-status=N" 3 silent --expected-status=3 "$work/trace-only" 3
check "--expected-status= with a non-integer value" 64 \
  "message:requires an integer from 0 to 255" \
  --expected-status=x "$work/trace-only" 1
# `-h` and `--help` print a usage message.
check "--help" 0 "message:^Usage: " --help
check "-h" 0 "message:^Usage: " -h
# `--` ends the options, so the command may start with "-".
check "-- before the command" 0 silent -- "$work/trace-only" 0
ln -s "$work/trace-only" "$work/-dash-command"
saved_path="$PATH"
PATH="$work:$PATH"
check "-- before a command that starts with a dash" 3 report -- -dash-command 3
PATH="$saved_path"

# `--help` and a usage error work even when no temporary directory can be
# created.
saved_tmpdir="$TMPDIR"
TMPDIR="$work/no-such-directory"
check "--help without a temporary directory" 0 "message:^Usage: " --help
check "usage error without a temporary directory" 64 "message:^Usage: "
TMPDIR="$saved_tmpdir"

# A command with the same name as one of `cronic`'s shell functions runs the
# program of that name, not the function.
function_names=$(sed -n 's/^\(cronic_[a-z_]*\)() {$/\1/p' "$CRONIC")
if [ -z "$function_names" ]; then
  echo "FAIL: found no shell functions in $CRONIC"
  status=1
fi
mkdir "$work/bin"
for name in $function_names; do
  cat > "$work/bin/$name" << 'EOF'
#!/bin/sh
exit 3
EOF
  chmod +x "$work/bin/$name"
done
saved_path="$PATH"
PATH="$work/bin:$PATH"
for name in $function_names; do
  check "command named $name" 3 silent --expected-status 3 "$name"
done
PATH="$saved_path"

# The wrapped command sees the caller's exported variables unchanged.  For
# each variable that `cronic` assigns, the caller exports that name in
# uppercase, both with and without any "cronic_" prefix (for example,
# `CRONIC_OUT` and `OUT`).  `TMPDIR` is omitted, because `cronic` reads it.
# The lowercase names that `cronic` assigns, such as `cronic_out`, are not
# exported:  `cronic` does overwrite them, but environment variables
# conventionally have uppercase names.
variable_names=$(sed -n 's/^ *\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$CRONIC" | sort -u)
if [ -z "$variable_names" ]; then
  echo "FAIL: found no variables in $CRONIC"
  status=1
fi
exported_names=
for name in $variable_names; do
  upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')
  for exported in "$upper" "${upper#CRONIC_}"; do
    [ "$exported" = TMPDIR ] && continue
    exported_names="$exported_names $exported"
  done
done
cat > "$work/check-variables" << 'EOF'
#!/bin/sh
for name; do
  eval "value=\${$name-}"
  [ "$value" = "caller's $name" ] || exit 3
done
EOF
chmod +x "$work/check-variables"
for name in $exported_names; do
  eval "$name=\"caller's \$name\""
  export "${name?}"
done
# shellcheck disable=SC2086  # each name is a separate argument.
check "caller's exported variables" 0 silent "$work/check-variables" $exported_names
# shellcheck disable=SC2086  # each name is a separate argument.
unset $exported_names

exit "$status"
