#!/bin/sh

# Tests `cronic`, concentrating on the case where the wrapped command's stderr
# consists only of `PS4` execution-trace lines, as when the command runs under
# `set -x` and writes no other error output.
#
# `cronic` filters trace lines out of stderr with `grep -v`, which exits with
# status 1 when it selects no lines.  `cronic` runs under `set -e`, so an
# unguarded `grep -v` would abort the script at that point:  no report would be
# printed, and the exit status would be grep's 1 rather than the wrapped
# command's.  (The temporary files would still be removed, by `cronic`'s EXIT
# trap, so the left-behind-files check in `check` does not detect that bug.)
#
# The checks that catch that bug are the "trace-only stderr" checks that use
# `stderr-lines` with a literal PS4, and the "nested trace in stderr" check,
# whose bash script writes its trace lines to stderr whatever the bash version.
# All of them run only when the test is not run as root.  The checks that use
# `trace-only`, a bash script, catch it only under a bash earlier than 4.1:  a
# later bash writes its trace lines to BASH_XTRACEFD, so `cronic` sees no trace
# lines in stderr and does not run `grep -v`.

set -eu

# Do not let the user's environment file run in `cronic` or in the bash commands
# below.  It could write to stderr, especially when an exported SHELLOPTS turns
# on `-u` for it.
unset BASH_ENV
# Use the default PS4, which the goal files and the trace lines below assume.
unset PS4

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

# A bash that supports BASH_XTRACEFD and the allocation of a file descriptor
# (bash 4.1 or later) writes its trace lines to a separate file, so they are
# not error output, whatever PS4 is.  An earlier bash, such as macOS's
# /bin/bash, writes them to stderr, where `cronic` cannot recognize them when
# PS4 contains an expansion or an escape, so it reports them as error output.
#
# This tests for the features themselves, rather than for the bash version
# that `cronic` tests for, so that it detects a wrong version test in `cronic`.
# `cronic` and the bash scripts below all run under the first `bash` in PATH,
# so that is the bash tested here.  The probe checks whether a trace line
# reaches the file, rather than whether bash writes to stderr, because bash can
# write an unrelated warning to stderr, such as for an uninstalled locale.
if bash -c 'exec {fd}> "$1" && BASH_XTRACEFD=$fd && set -x && :' \
  bash "$work/xtracefd-probe" 2> /dev/null && [ -s "$work/xtracefd-probe" ]; then
  bash_has_xtracefd=true
else
  bash_has_xtracefd=false
fi

# A command whose stderr is nothing but trace lines.
cat > "$work/trace-only" << 'EOF'
#!/usr/bin/env bash
set -x
echo "the standard output"
exit "$1"
EOF
chmod +x "$work/trace-only"

# A command that writes real error output in addition to trace lines.
cat > "$work/trace-and-stderr" << 'EOF'
#!/usr/bin/env bash
set -x
echo "a real error" 1>&2
exit "$1"
EOF
chmod +x "$work/trace-and-stderr"

# A command whose stderr is nothing but `make` directory-change notices.  Both
# the top-level form (`make:`) and the recursive form (`make[1]:`) appear, as do
# the quoting of GNU make 3.81 (macOS's /usr/bin/make) and the other names
# that GNU make runs under; all must be filtered out of the reduced error
# output.
cat > "$work/make-noise" << 'EOF'
#!/bin/sh
echo "make: Entering directory '/tmp/x'" 1>&2
echo "make[1]: Entering directory '/tmp/x/sub'" 1>&2
echo 'make[2]: Entering directory `/tmp/x/sub/old'"'" 1>&2
echo 'make[2]: Leaving directory `/tmp/x/sub/old'"'" 1>&2
echo "gmake[2]: Entering directory '/tmp/x/sub/g'" 1>&2
echo "gmake[2]: Leaving directory '/tmp/x/sub/g'" 1>&2
echo "gnumake[2]: Entering directory '/tmp/x/sub/gnu'" 1>&2
echo "gnumake[2]: Leaving directory '/tmp/x/sub/gnu'" 1>&2
echo "mingw32-make[2]: Entering directory '/tmp/x/sub/mingw'" 1>&2
echo "mingw32-make[2]: Leaving directory '/tmp/x/sub/mingw'" 1>&2
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

# A command that writes a trace line and then an error line that contains a
# NUL byte and a byte that is invalid in UTF-8, so that `grep` would treat the
# output as binary.
cat > "$work/binary-stderr" << 'EOF'
#!/bin/sh
printf '[trace] echo hi\n' 1>&2
printf 'bad \377\000 error\n' 1>&2
EOF
chmod +x "$work/binary-stderr"

# A bash command whose trace lines go to stderr, as under a bash earlier than
# 4.1, whatever the bash version.  Its trace lines are nested 3 deep.
cat > "$work/nested-trace" << 'EOF'
#!/usr/bin/env bash
unset BASH_XTRACEFD
set -x
outer=$(inner=$(echo deepest); echo "$inner")
echo "$outer"
exit "$1"
EOF
chmod +x "$work/nested-trace"

# A command that writes, to stderr, lines that start with `+` but are not trace
# lines.
cat > "$work/plus-stderr" << 'EOF'
#!/bin/sh
echo "+++ b/file" 1>&2
echo "++ conflict" 1>&2
EOF
chmod +x "$work/plus-stderr"

# A command that writes each of its arguments, as a line, to stderr.  It stands
# for a shell other than bash, which writes its trace lines to stderr.
cat > "$work/stderr-lines" << 'EOF'
#!/bin/sh
printf '%s\n' "$@" 1>&2
EOF
chmod +x "$work/stderr-lines"

# Runs `cronic` with SHELLOPTS set to its first argument and exported, and
# with these exported shell functions:
#  * `fail_then_continue` runs `false` and then prints a line.
#  * `fail_in_pipeline` runs a pipeline whose first command fails.
#  * `report_cronic_variables` writes to stderr any variable or function of
#    `cronic`'s that it can see.
cat > "$work/cronic-with-shellopts" << 'EOF2'
#!/bin/bash
fail_then_continue() {
  false
  echo "after the failure"
}
fail_in_pipeline() {
  false | true
}
report_cronic_variables() {
  compgen -v -A function cronic_ >&2
  return 0
}
export -f fail_then_continue fail_in_pipeline report_cronic_variables
shellopts="$1"
shift
exec env SHELLOPTS="$shellopts" "$REAL_CRONIC" "$@"
EOF2
chmod +x "$work/cronic-with-shellopts"

# temp_files: prints `cronic`'s temporary files, in a canonical order.
temp_files() {
  find "$TMPDIR" -mindepth 1 -maxdepth 1 2> /dev/null | sort
}

# run_cronic DESCRIPTION EXPECTED-STATUS COMMAND...: runs COMMAND, which runs
# `cronic`, with its standard output in "$work/output" and its error output in
# "$work/stderr".  If COMMAND exits with a status other than EXPECTED-STATUS,
# or leaves temporary files behind, then reports a failure and returns 1.
run_cronic() {
  description="$1"
  expected_status="$2"
  shift 2

  before="$(temp_files)"
  actual_status=0
  "$@" > "$work/output" 2> "$work/stderr" || actual_status=$?
  after="$(temp_files)"

  if [ "$actual_status" != "$expected_status" ]; then
    echo "FAIL: $description: exit status $actual_status, expected $expected_status"
    cat "$work/output" "$work/stderr"
    status=1
    return 1
  fi
  if [ "$before" != "$after" ]; then
    echo "FAIL: $description: temporary files were left behind:"
    echo "$after"
    status=1
    return 1
  fi
}

# check_goals DESCRIPTION OUTPUT-GOAL STDERR-GOAL COMMAND...: runs COMMAND,
# which runs `cronic`, and checks that it exits with status 0, leaves no
# temporary files, and writes the contents of OUTPUT-GOAL to standard output
# and the contents of STDERR-GOAL to stderr.
check_goals() {
  description="$1"
  output_goal="$2"
  stderr_goal="$3"
  shift 3

  run_cronic "$description" 0 "$@" || return 0
  if cmp -s "$output_goal" "$work/output" && cmp -s "$stderr_goal" "$work/stderr"; then
    echo "PASS: $description"
  else
    echo "FAIL: $description: output:"
    cat "$work/output"
    echo "stderr:"
    cat "$work/stderr"
    status=1
  fi
}

# check_trace_goals: like check_goals, but skips the check if bash lacks
# BASH_XTRACEFD, so that the report has no "TRACE OUTPUT".
check_trace_goals() {
  if [ "$bash_has_xtracefd" = false ]; then
    echo "SKIP: $1, because bash is older than 4.1"
    return 0
  fi
  check_goals "$@"
}

# check DESCRIPTION EXPECTED-STATUS EXPECTED-OUTPUT COMMAND...: runs `cronic`
# on COMMAND and checks its exit status, whether it printed a report, and that
# it left no temporary files behind.  EXPECTED-OUTPUT is "silent", "report",
# "report:TEXT", which also requires TEXT to appear in the report,
# "report-once:TEXT", which also requires TEXT to appear on exactly one line of
# the report, or "message:TEXT", which requires TEXT to appear in output that
# need not be a report.
check() {
  description="$1"
  expected_status="$2"
  expected_output="$3"
  shift 3

  run_cronic "$description" "$expected_status" "$CRONIC" "$@" || return 0
  # The checks below examine both outputs, because `cronic` writes its usage
  # messages to stderr.
  cat "$work/stderr" >> "$work/output"

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
    report-once:*)
      if [ "$(grep -c -e "${expected_output#*:}" "$work/output")" -ne 1 ]; then
        echo "FAIL: $description: expected exactly one line of the output to" \
          "contain \"${expected_output#*:}\", but got:"
        cat "$work/output"
        status=1
        return
      fi
      ;;
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

# Error output that does not end with a newline is shown once, on a line of
# its own, both when trace lines are filtered out of it and when they are not.
check "stderr without a final newline" 0 "report-once:^oops$" \
  sh -c 'printf oops >&2'
# shellcheck disable=SC2016 # The expansion is for the traced command to do.
PS4='+$X '
export PS4
check "stderr without a final newline, unfiltered" 0 "report-once:^oops$" \
  sh -c 'printf oops >&2'
unset PS4

# Error output that `grep` would treat as binary is still reported.
check "binary stderr" 0 "report:error$" "$work/binary-stderr"

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
# Output that the subshell writes after the command finishes, such as from an
# EXIT trap that the command sets, is captured rather than leaked.
check "EXIT trap writes to stderr" 0 "report:^from the trap$" \
  trap 'echo "from the trap" >&2' EXIT
check "EXIT trap writes to stdout" 0 silent trap 'echo "from the trap"' EXIT
# A builtin runs with `set +u`, as it would in an ordinary shell.
# shellcheck disable=SC2016 # The expansion is for the wrapped command to do.
check "builtin with an unset variable" 0 silent \
  eval ': "$cronic_test_unset_variable"'

# When SHELLOPTS is exported, `cronic`'s own `-e` and `-u` options do not reach
# the wrapped command, but the caller's options do.
REAL_CRONIC="$CRONIC"
export REAL_CRONIC
CRONIC="$work/cronic-with-shellopts"
default_shellopts=braceexpand:hashall:interactive-comments
# shellcheck disable=SC2016 # The expansion is for the wrapped command to do.
check "exported SHELLOPTS, command reads an unset variable" 0 silent \
  "$default_shellopts" bash -c ': "$cronic_test_unset_variable"'
check "exported SHELLOPTS, command ignores a failure" 0 silent \
  "$default_shellopts" bash -c 'false; :'
# shellcheck disable=SC2016 # The expansion is for the wrapped command to do.
check "exported SHELLOPTS with nounset, command reads an unset variable" 127 \
  "report:unbound variable" \
  "$default_shellopts:nounset" bash -c ': "$cronic_test_unset_variable"'
check "exported SHELLOPTS with errexit, command ignores a failure" 1 report \
  "$default_shellopts:errexit" bash -c 'false; :'
# With allexport exported, `cronic` does not export its own variables to the
# command, but a variable that the command assigns is exported.
check "exported SHELLOPTS with allexport, no cronic variables exported" 0 silent \
  "$default_shellopts:allexport" sh -c '! env | grep -q "^cronic_"'
# shellcheck disable=SC2016 # The expansion is for the wrapped command to do.
check "exported SHELLOPTS with allexport, command's variable exported" 0 silent \
  "$default_shellopts:allexport" \
  eval 'cronic_test_variable=1; sh -c "[ \"\$cronic_test_variable\" = 1 ]"'
# With xtrace exported, a successful command with only trace output on stderr
# produces no output at all:  `cronic` does not trace itself.
check "exported SHELLOPTS with xtrace, trace-only stderr" 0 silent \
  "$default_shellopts:xtrace" "$work/trace-only" 0
# With xtrace exported, the report's trace section is the command's own trace,
# with nothing that `cronic` did to set up the command's options or to run the
# command.  Bash writes the trace via BASH_XTRACEFD, so it appears under
# "TRACE OUTPUT".
cat > "$work/trace-report.goal" << EOF
Cronic detected failure or error output for the command:
$work/trace-and-stderr 0

RESULT CODE: 0  (success)

ERROR OUTPUT:
a real error

STANDARD OUTPUT:

TRACE OUTPUT:
+ set -x
+ echo 'a real error'
+ exit 0

END OF CRONIC OUTPUT.
EOF
check_trace_goals "exported SHELLOPTS with xtrace, trace output" \
  "$work/trace-report.goal" /dev/null \
  "$CRONIC" "$default_shellopts:xtrace" "$work/trace-and-stderr" 0
# With xtrace exported, the trace lines of a builtin are nested 1 deeper than
# the builtin, whose own trace is the line that runs it, which is not reported.
# The trace of an EXIT trap that the builtin sets is reported, even if the
# builtin returns normally rather than calling `exit`.
cat > "$work/exit-trap-trace-report.goal" << 'EOF'
Cronic detected failure or error output for the command:
eval trap 'echo trapped >&2' EXIT

RESULT CODE: 0  (success)

ERROR OUTPUT:
trapped

STANDARD OUTPUT:

TRACE OUTPUT:
++ trap 'echo trapped >&2' EXIT
++ echo trapped

END OF CRONIC OUTPUT.
EOF
check_trace_goals "exported SHELLOPTS with xtrace, EXIT trap of a builtin" \
  "$work/exit-trap-trace-report.goal" /dev/null \
  "$CRONIC" "$default_shellopts:xtrace" eval "trap 'echo trapped >&2' EXIT"

# The caller's `-e` applies within an exported shell function that is the
# command, and the caller's lack of `-e` does too.
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
# functions.
check "exported function sees none of cronic's variables or functions" 0 silent \
  "$default_shellopts" report_cronic_variables
check "exported function sees none of cronic's variables or functions, xtrace" \
  0 silent "$default_shellopts:xtrace" report_cronic_variables
# ... nor a variable that is not exported, which BASH_ENV set within `cronic`.
echo "cronic_from_bash_env=unexported" > "$work/bash-env"
BASH_ENV="$work/bash-env"
export BASH_ENV
check "exported function does not see unexported variable from BASH_ENV" 0 \
  silent "$default_shellopts" report_cronic_variables
unset BASH_ENV
# Under the caller's allexport, the command's environment contains none of
# `cronic`'s variables, nor the POSIXLY_CORRECT that `cronic` assigns.  The
# command is `bash` rather than `sh`, because when `sh` is bash, as on macOS,
# it assigns POSIXLY_CORRECT itself, and allexport exports it.
check "exported SHELLOPTS with allexport, environment has no cronic variable" 0 \
  silent "$default_shellopts:allexport" \
  bash -c 'env | grep -E "^(cronic_|POSIXLY_CORRECT=)" >&2; :'
CRONIC="$REAL_CRONIC"

# The wrapped command sees the caller's exported variables unchanged.  For
# each variable that `cronic` assigns, the caller exports that name in
# uppercase, both with and without any "cronic_" prefix (for example,
# `CRONIC_OUT` and `OUT`).  `TMPDIR` is omitted, because `cronic` reads it.
# The lowercase names that `cronic` assigns, such as `cronic_out`, are not
# exported here, because environment variables conventionally have uppercase
# names; the next test checks a few of them.
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
# `check-variables` runs under bash rather than `sh`, because when `sh` is
# bash, as on macOS, it replaces the caller's POSIXLY_CORRECT by "y".
cat > "$work/check-variables" << 'EOF'
#!/usr/bin/env bash
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

# Names that start with `cronic_` are reserved:  the command does not see a
# variable or function with such a name that the caller exported.  The caller
# also exports functions named like builtins that `cronic` uses, which must not
# run in place of those builtins, though the command does see them.
cat > "$work/cronic-with-cronic-names" << 'EOF'
#!/bin/bash
cronic_mine() {
  exit 3
}
cronic_debug="caller's cronic_debug"
export -f cronic_mine
export cronic_debug
builtin() { echo "function builtin ran" >&2; }
compgen() { echo "function compgen ran" >&2; }
declare() { echo "function declare ran" >&2; }
eval() { echo "function eval ran" >&2; }
export() { echo "function export ran" >&2; }
read() { echo "function read ran" >&2; }
set() { echo "function set ran" >&2; }
unset() { echo "function unset ran" >&2; }
command export -f builtin compgen declare eval export read set unset
exec "$REAL_CRONIC" "$@"
EOF
chmod +x "$work/cronic-with-cronic-names"
CRONIC="$work/cronic-with-cronic-names"
# shellcheck disable=SC2016 # The expansion is for `sh` to do.
check "caller's exported cronic_ variable is not seen" 0 silent \
  sh -c '[ -z "${cronic_debug+set}" ]'
check "caller's exported cronic_ function is not seen" 0 silent \
  bash -c '! command declare -F cronic_mine'
check "caller's exported functions are seen" 0 silent \
  bash -c 'command declare -F set unset > /dev/null'
CRONIC="$REAL_CRONIC"

# The command does not see the caller's exported function named `builtin`,
# which `cronic` removes so that it can run builtins via `builtin`, but it does
# see one named `command`.
cat > "$work/cronic-with-builtin-and-command" << 'EOF'
#!/bin/bash
builtin() { echo "function builtin ran"; }
command() { echo "function command ran"; }
export -f builtin command
exec "$REAL_CRONIC" "$@"
EOF
chmod +x "$work/cronic-with-builtin-and-command"
CRONIC="$work/cronic-with-builtin-and-command"
# shellcheck disable=SC2016 # The expansion is for `bash` to do.
check "caller's exported function named builtin is not seen, command is" 1 \
  "report:^no builtin, function command ran$" \
  bash -c 'declare -F builtin || echo "no builtin, $(command)"; false'
CRONIC="$REAL_CRONIC"

# A function whose name is not an identifier reaches the command, even when
# the caller exported errexit.  A function that BASH_ENV defined, rather than
# one that the caller exported, is not exported to the command.
cat > "$work/cronic-with-odd-names" << 'EOF'
#!/bin/bash
my-fn() {
  echo "my-fn ran"
}
export -f my-fn
set -o errexit
export SHELLOPTS
exec "$REAL_CRONIC" "$@"
EOF
chmod +x "$work/cronic-with-odd-names"
echo 'from_bash_env() { :; }' > "$work/bash-env"
CRONIC="$work/cronic-with-odd-names"
BASH_ENV="$work/bash-env"
export BASH_ENV
check "caller's exported function whose name is not an identifier" 1 \
  "report:my-fn ran" bash -c 'my-fn; false'
check "function from BASH_ENV is not exported" 0 silent \
  bash -c '! printenv "BASH_FUNC_from_bash_env%%"'
unset BASH_ENV
CRONIC="$REAL_CRONIC"

# An alias that BASH_ENV defined does not change the caller's exported function,
# just as it would not if bash ran the function directly.  BASH_ENV turns on
# posix mode, because bash turns off expand_aliases when it leaves posix mode.
# The caller sets BASH_ENV only for `cronic`, so that the caller's own
# definition of the function contains no alias.
cat > "$work/cronic-with-alias" << 'EOF'
#!/bin/bash
print_hi() {
  echo hi
}
export -f print_hi
BASH_ENV="$1"
export BASH_ENV
shift
exec "$REAL_CRONIC" "$@"
EOF
chmod +x "$work/cronic-with-alias"
cat > "$work/bash-env" << 'EOF'
shopt -s expand_aliases
alias echo='echo ALIASED'
set -o posix
EOF
CRONIC="$work/cronic-with-alias"
check "alias from BASH_ENV does not change exported function" 1 "report:^hi$" \
  "$work/bash-env" bash -c 'print_hi; false'
CRONIC="$REAL_CRONIC"

# A function that BASH_ENV made readonly cannot be removed, so `cronic` does not
# run the command, but it fails with an error message rather than silently.
echo 'grep() { echo "function grep ran"; }; readonly -f grep' > "$work/bash-env"
BASH_ENV="$work/bash-env"
export BASH_ENV
check "readonly function from BASH_ENV" 1 "message:readonly function" true
# Likewise, a `cronic_` variable that BASH_ENV made readonly cannot be removed,
# so the command, which would exit with status 5, does not run.
echo 'readonly cronic_mine=x' > "$work/bash-env"
check "readonly cronic_ variable from BASH_ENV" 1 "report:readonly variable" \
  sh -c 'exit 5'
unset BASH_ENV

# `bash -x cronic` traces neither `cronic` itself nor the line that runs the
# command.  The command does not inherit xtrace, because SHELLOPTS is not
# exported, so its own `set -x` is not traced.
grep -v '^+ set -x$' "$work/trace-report.goal" > "$work/bash-x-trace-report.goal"
check_trace_goals "bash -x cronic, trace output" \
  "$work/bash-x-trace-report.goal" /dev/null \
  bash -x "$CRONIC" "$work/trace-and-stderr" 0

# When `bash_has_xtracefd` is true, bash writes its trace lines to a separate
# file, so they are not error output, whatever PS4 is.
export PS4
# shellcheck disable=SC2016 # The expansion is for the traced command to do.
PS4='+${LINENO}: '
# The real error is reported, whether or not the trace lines are too.
check "bash, PS4 with expansions, trace lines and real stderr" 0 \
  "report:^a real error$" "$work/trace-and-stderr" 0
check "bash, PS4 with expansions, trace in the report" 3 \
  "report:echo 'the standard output'$" "$work/trace-only" 3
if [ "$bash_has_xtracefd" = true ]; then
  check "bash, PS4 with expansions, trace-only stderr" 0 silent \
    "$work/trace-only" 0
  PS4='+\D{%H}: '
  check "bash, PS4 with an escape, trace-only stderr" 0 silent \
    "$work/trace-only" 0
fi
PS4='[trace] '
check "bash, PS4 with metacharacters, trace-only stderr" 0 silent \
  "$work/trace-only" 0

# The tests below concern trace lines in stderr, as written by a shell other
# than bash or by a bash that does not use BASH_XTRACEFD; they are recognized
# by PS4.  Bash running as root does not import PS4 from the environment, so
# `cronic` would see the default PS4, and these tests are skipped.
if [ "$(id -u)" -eq 0 ]; then
  echo "SKIP: tests of PS4 in stderr, because bash ignores PS4 when run as root"
  unset PS4
  exit "$status"
fi

# An earlier bash writes its trace lines to stderr, and when PS4 contains an
# expansion or an escape, they are reported.
if [ "$bash_has_xtracefd" = false ]; then
  # shellcheck disable=SC2016 # The expansion is for the traced command to do.
  PS4='+${LINENO}: '
  check "bash before 4.1, PS4 with expansions, trace-only stderr" 0 \
    "report:^+3: echo 'the standard output'$" "$work/trace-only" 0
  PS4='+\D{%H}: '
  check "bash before 4.1, PS4 with an escape, trace-only stderr" 0 \
    "report:^+[0-9][0-9]: echo 'the standard output'$" "$work/trace-only" 0
fi

# Trace lines are recognized when PS4 contains regular-expression
# metacharacters or quotes, and the metacharacters do not match other lines.
PS4='[trace] '
check "PS4 with metacharacters, trace-only stderr" 0 silent \
  "$work/stderr-lines" "[trace] echo hi" "[[trace] echo nested" \
  "[[[trace] echo nested more"
# The same, for the trace lines that bash writes to stderr.
check "bash, PS4 with metacharacters, nested trace in stderr" 0 silent \
  "$work/nested-trace" 0
check "bash, PS4 with metacharacters, nested trace in the report" 3 \
  "report:^\[\[\[trace\] echo deepest$" "$work/nested-trace" 3
check "PS4 with metacharacters, trace lines and real stderr" 0 \
  "report:^a real error$" \
  "$work/stderr-lines" "[trace] echo hi" "a real error"
check "PS4 with metacharacters, trace lines and binary stderr" 0 \
  "report:error$" "$work/binary-stderr"
PS4='+.* '
check "PS4 with metacharacters, error line that they would match" 0 \
  "report:^+++ b/file$" "$work/stderr-lines" "+++ b/file"
PS4="+\"it's\" "
check "PS4 with quotes, trace-only stderr" 0 silent \
  "$work/stderr-lines" "+\"it's\" echo hi" "++\"it's\" echo nested"
# A multibyte first character is repeated as a whole, even in the C locale.
PS4='→ '
LC_ALL=C
export LC_ALL
check "PS4 with a multibyte first character, trace-only stderr" 0 silent \
  "$work/stderr-lines" "→ echo hi" "→→ echo nested"
unset LC_ALL
# When PS4 contains an expansion, an escape, or a newline, no line is treated
# as a trace line, so trace lines are reported, and so is an error line that
# resembles one.
# shellcheck disable=SC2016 # The expansion is for the traced command to do.
PS4='+${LINENO}: '
check "PS4 with expansions, trace-only stderr" 0 \
  "report:^+3: echo hi$" "$work/stderr-lines" "+3: echo hi"
check "PS4 with expansions, error line that starts with +" 0 \
  "report:^+++ b/file$" "$work/stderr-lines" "+++ b/file"
# shellcheck disable=SC2016 # The expansion is for the traced command to do.
PS4='+${BASH_SOURCE}:${LINENO}: '
check "PS4 with several expansions, error line that resembles a trace line" 0 \
  "report:^+++ conflict: in file.c$" "$work/stderr-lines" "+++ conflict: in file.c"
PS4='+\D{%H}: '
check "PS4 with an escape, trace-only stderr" 0 \
  "report:^+12: echo hi$" "$work/stderr-lines" "+12: echo hi"
# shellcheck disable=SC2016 # The expansion is for the traced command to do.
PS4='+$LINENO'
check "PS4 ending with an expansion, error line that starts with +" 0 \
  "report:^+ error happened$" "$work/stderr-lines" "+ error happened"
PS4='a
b '
check "PS4 with a newline, error line that contains its second line" 0 \
  "report:^error: bad b input$" "$work/stderr-lines" "error: bad b input"
unset PS4

exit "$status"
