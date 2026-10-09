#!/bin/sh

# Tests `cronic`, concentrating on the case where the wrapped command's stderr
# consists only of `PS4` execution-trace lines, as when the command runs under
# `set -x` and writes no other error output.
#
# `cronic` filters trace lines out of stderr with `grep -v`, which exits with
# status 1 when it selects no lines.  `cronic` runs under `set -e`, so an
# unguarded `grep -v` would abort the script at that point:  no report would be
# printed, the exit status would be grep's 1 rather than the wrapped command's,
# and the temporary files would be left behind.

set -eu

# Do not let the user's environment file run in `cronic` or in the bash commands
# below.  It could write to stderr, especially when an exported SHELLOPTS turns
# on `-u` for it.
unset BASH_ENV
# Do not pass this script's own options, such as `-e` and `-u`, to `cronic` and
# to the commands below.  If SHELLOPTS is exported, then run this script again
# without it, because bash makes SHELLOPTS read-only, so it cannot be unset.
if env | grep -q '^SHELLOPTS='; then
  env -u SHELLOPTS "$0" "$@"
  exit
fi

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

# A bash command that reads an unset variable.
cat > "$work/read-unset" << 'EOF'
#!/bin/bash
unset CRONIC_TEST_UNSET_VARIABLE
echo "value: ${CRONIC_TEST_UNSET_VARIABLE}" > /dev/null
exit "$1"
EOF
chmod +x "$work/read-unset"

# A bash command in which a command fails before the script exits.
cat > "$work/ignore-failure" << 'EOF'
#!/bin/bash
false
exit "$1"
EOF
chmod +x "$work/ignore-failure"

# Runs `cronic` with SHELLOPTS set to its first argument and exported.
cat > "$work/cronic-with-shellopts" << 'EOF'
#!/bin/sh
shellopts="$1"
shift
exec env SHELLOPTS="$shellopts" "$REAL_CRONIC" "$@"
EOF
chmod +x "$work/cronic-with-shellopts"

# Runs `cronic` with SHELLOPTS set to its first argument and exported, and
# with these exported shell functions:
#  * `fail_then_continue` runs `false` and then prints a line.
#  * `fail_in_pipeline` runs a pipeline whose first command fails.
#  * `report_cronic_variables` writes to stderr any variable or function of
#    `cronic`'s that it can see.
cat > "$work/cronic-with-function" << 'EOF2'
#!/bin/bash
fail_then_continue() {
  false
  echo "after the failure"
}
fail_in_pipeline() {
  false | true
}
report_cronic_variables() {
  set | grep '^cronic_' >&2
  declare -F | grep ' cronic_' >&2
  return 0
}
export -f fail_then_continue fail_in_pipeline report_cronic_variables
shellopts="$1"
shift
exec env SHELLOPTS="$shellopts" "$REAL_CRONIC" "$@"
EOF2
chmod +x "$work/cronic-with-function"

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

# The command may be a shell builtin.
check "builtin command" 0 silent :
# A builtin that would end the shell does not prevent the report.
check "exit builtin" 3 report exit 3
check "exec builtin" 3 report exec "$work/trace-only" 3

# A program whose name is that of a function of `cronic`'s runs rather than the
# function.
cat > "$work/bin/cronic_cleanup" << 'EOF'
#!/bin/sh
echo "the program named cronic_cleanup ran" 1>&2
exit 4
EOF
chmod +x "$work/bin/cronic_cleanup"
saved_path="$PATH"
PATH="$work/bin:$PATH"
check "program named cronic_cleanup" 4 \
  "report:^the program named cronic_cleanup ran$" cronic_cleanup
PATH="$saved_path"

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
# With xtrace exported, a successful command with only trace output on stderr
# produces no output at all:  `cronic` does not trace itself.
check "exported SHELLOPTS with xtrace, trace-only stderr" 0 silent \
  "$default_shellopts:xtrace" "$work/trace-only" 0
# With xtrace exported, the report's trace section is the trace of running the
# command, followed by the command's own trace, with nothing that `cronic` did
# to set up the command's options.
before="$(temp_files)"
xtrace_status=0
"$CRONIC" "$default_shellopts:xtrace" "$work/trace-and-stderr" 0 \
  > "$work/output" 2> "$work/stderr" || xtrace_status=$?
after="$(temp_files)"
if [ "$xtrace_status" != 0 ]; then
  echo "FAIL: exported SHELLOPTS with xtrace: exit status $xtrace_status, expected 0"
  status=1
fi
if [ -s "$work/stderr" ]; then
  echo "FAIL: exported SHELLOPTS with xtrace: cronic wrote to stderr:"
  cat "$work/stderr"
  status=1
fi
if [ "$before" != "$after" ]; then
  echo "FAIL: exported SHELLOPTS with xtrace: temporary files were left behind:"
  echo "$after"
  status=1
fi
sed -n '/^TRACE-ERROR OUTPUT:$/,/^$/p' "$work/output" > "$work/trace-section"
cat > "$work/trace-section.goal" << EOF
TRACE-ERROR OUTPUT:
+ $work/trace-and-stderr 0
+ set -x
+ echo 'a real error'
a real error
+ exit 0

EOF
if cmp -s "$work/trace-section.goal" "$work/trace-section"; then
  echo "PASS: exported SHELLOPTS with xtrace, trace output"
else
  echo "FAIL: exported SHELLOPTS with xtrace, trace output: got:"
  cat "$work/output"
  status=1
fi

# With verbose exported, a successful command produces no report:  `cronic`
# does not echo, into the command's error output, the commands that restore the
# caller's options.  (`cronic` does echo its own first lines to its stderr.)
verbose_status=0
"$CRONIC" "$default_shellopts:verbose" true > "$work/output" 2> /dev/null \
  || verbose_status=$?
if [ "$verbose_status" = 0 ] && [ ! -s "$work/output" ]; then
  echo "PASS: exported SHELLOPTS with verbose"
else
  echo "FAIL: exported SHELLOPTS with verbose: exit status $verbose_status, output:"
  cat "$work/output"
  status=1
fi

# The caller's `-e` applies within an exported shell function that is the
# command, and the caller's lack of `-e` does too.
CRONIC="$work/cronic-with-function"
check "exported SHELLOPTS with errexit, exported function ignores a failure" 1 \
  report "$default_shellopts:errexit" fail_then_continue
check "exported SHELLOPTS, exported function ignores a failure" 0 silent \
  "$default_shellopts" fail_then_continue
# Every one of the caller's options applies, not only `-e`, `-u`, and `-x`.
check "exported SHELLOPTS with pipefail, exported function" 1 report \
  "$default_shellopts:pipefail" fail_in_pipeline
check "exported SHELLOPTS without pipefail, exported function" 0 silent \
  "$default_shellopts" fail_in_pipeline
# A shell function that is the command does not see `cronic`'s variables or
# function.
check "exported function sees none of cronic's variables or function" 0 silent \
  "$default_shellopts" report_cronic_variables
# ... nor a variable that is not exported, which BASH_ENV set within `cronic`.
echo "cronic_from_bash_env=unexported" > "$work/bash-env"
BASH_ENV="$work/bash-env"
export BASH_ENV
check "exported function does not see unexported variable from BASH_ENV" 0 \
  silent "$default_shellopts" report_cronic_variables
unset BASH_ENV
CRONIC="$REAL_CRONIC"

# `cronic` does not change a variable that the caller exported.  For each
# variable that `cronic` assigns, the caller exports that name in uppercase,
# both with and without any "cronic_" prefix (for example, `CRONIC_OUT` and
# `OUT`).  `TMPDIR` is omitted, because `cronic` reads it.
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

# The command sees a variable that the caller exported even if its name is that
# of one of `cronic`'s own variables, though that is unconventional.
cat > "$work/check-cronic-variables" << 'EOF'
#!/bin/sh
[ "$cronic_debug" = "caller's cronic_debug" ] \
  && [ "$cronic_tmpdir" = "caller's cronic_tmpdir" ] || exit 3
EOF
chmod +x "$work/check-cronic-variables"
cronic_debug="caller's cronic_debug"
cronic_tmpdir="caller's cronic_tmpdir"
export cronic_debug cronic_tmpdir
check "caller's exported variables named like cronic's" 0 silent \
  "$work/check-cronic-variables"
unset cronic_debug cronic_tmpdir

# `cronic` does not remove a function that the caller exported, whether its
# name is one of `cronic`'s own functions or merely starts like them.  The
# function is visible both to the command and to the command's children.
cat > "$work/cronic-with-cronic-functions" << 'EOF'
#!/bin/bash
cronic_mine() {
  exit 3
}
cronic_usage() {
  exit 4
}
export -f cronic_mine cronic_usage
exec "$1" "${@:2}"
EOF
chmod +x "$work/cronic-with-cronic-functions"
CRONIC="$work/cronic-with-cronic-functions"
check "caller's exported function named cronic_mine" 3 silent \
  "$REAL_CRONIC" --expected-status 3 cronic_mine
check "caller's exported function named cronic_mine, in a child" 3 silent \
  "$REAL_CRONIC" --expected-status 3 bash -c cronic_mine
check "caller's exported function named cronic_usage" 4 silent \
  "$REAL_CRONIC" --expected-status 4 cronic_usage
CRONIC="$REAL_CRONIC"

# `bash -x cronic`, which does not export SHELLOPTS, traces `cronic` itself.
bash_x_status=0
bash -x "$CRONIC" "$work/trace-only" 0 > "$work/output" 2> "$work/stderr" \
  || bash_x_status=$?
if [ "$bash_x_status" = 0 ] && grep -q "cronic_debug=false" "$work/stderr"; then
  echo "PASS: bash -x traces cronic"
else
  echo "FAIL: bash -x traces cronic: exit status $bash_x_status, stderr:"
  cat "$work/stderr"
  status=1
fi

# Under `bash -x cronic`, the report's trace section contains nothing that
# `cronic` did to set up the command.  The command does not inherit xtrace, so
# its own `set -x` is not traced.
bash -x "$CRONIC" "$work/trace-and-stderr" 0 > "$work/output" 2> /dev/null \
  || true
sed -n '/^TRACE-ERROR OUTPUT:$/,/^$/p' "$work/output" > "$work/trace-section"
cat > "$work/bash-x-trace-section.goal" << EOF
TRACE-ERROR OUTPUT:
+ $work/trace-and-stderr 0
+ echo 'a real error'
a real error
+ exit 0

EOF
if cmp -s "$work/bash-x-trace-section.goal" "$work/trace-section"; then
  echo "PASS: bash -x cronic, trace output"
else
  echo "FAIL: bash -x cronic, trace output: got:"
  cat "$work/output"
  status=1
fi

exit "$status"
