#!/bin/sh

# The implementation shared by `ci-org-and-branch` and `git-changes`.
#
# Both scripts print variable settings for the client to `eval`.  They differ
# only in which "set-" script computes the values and in which variables they
# print, so each one sets a few variables and sources this file instead of
# repeating the argument parsing, the quoting, and the error handling.  A fix
# to any of that now applies to both scripts.  While this code was duplicated,
# a bug in the GitHub Actions code path was fixed in one copy and left in the
# other.
#
# This file is not a script to run; it is sourced, so that `exit` here exits
# the client and so that the variables that the "set-" script sets are visible
# here.  It is not part of this repository's interface:  a client uses
# `ci-org-and-branch` or `git-changes`, or better yet the corresponding "set-"
# script.
#
# Before sourcing this file, the client sets these variables:
# _ew_script_dir: the directory that contains these scripts.
# _ew_helper: the name of the "set-" script that computes the values.
# _ew_variables: the names of the variables to print, separated by spaces.
#   They are printed in the order given.
# The client does not pass its command-line arguments along, because sourcing
# preserves the positional parameters.

# Because this file is sourced, shellcheck can see neither where its inputs
# come from nor where its outputs go, and it reports every one of them.  The
# client assigns $_ew_script_dir, $_ew_helper, and $_ew_variables before
# sourcing this file; the `eval` at the bottom assigns $_ew_value; and the
# "set-" script that this file sources reads $PLUME_SCRIPTS, $CI_VERBOSE, and
# $CI_DEBUG -- but its name is computed, so shellcheck cannot follow it and
# does not see those reads.
#
# Each such report is suppressed on the one line that provokes it, rather than
# for the whole file.  A file-wide `disable=SC2154` would also hide a
# misspelling of this file's own variables:  writing `${_ew_verbos}` for
# `${_ew_verbose}` would silently make `--verbose` and `--debug` do nothing.
# No test would catch that, because no test runs with those flags -- and a
# diagnostic that never appears is not something a test can compare against.
# Line-specific directives leave that report in place.
#
# $_ew_default_organization is the exception:  it is read only as
# `${_ew_default_organization:-...}`, and shellcheck does not report an
# unassigned variable that has a default, so no directive here hides a
# misspelling of it.  `eval-quoting-test` catches that one, by requiring that
# the DEFAULT-ORGANIZATION argument reach $CI_ORGANIZATION in some case.
#
# (A comment line here must not begin with the word that starts a shellcheck
# directive, because shellcheck would try to parse the line as one.)

# When this file is sourced, "$0" is the client's name rather than this file's
# name; so if "$0" is this file's name, someone ran it instead of sourcing it.
case $0 in
  */eval-wrapper.sh | eval-wrapper.sh)
    echo "eval-wrapper.sh must be sourced (\`. eval-wrapper.sh\`), not run." >&2
    exit 2
    ;;
esac

### Functions

# Writes its argument, quoted so that the client's `eval` reads it back as one
# word.  A value may contain a shell metacharacter:  a git branch name may
# contain any of `$`, backquote, `;`, `&`, `|`, and `'`.
_ew_shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

### Arguments

# Every variable of this file's own is named with the "_ew_" prefix, so that
# nothing in the environment or in the client can turn on diagnostics that the
# command line did not request.
_ew_script_name="$(basename -- "$0")"
_ew_debug=""
_ew_verbose=""
_ew_default_organization=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --verbose)
      _ew_verbose="--verbose"
      ;;
    --debug)
      _ew_debug="--debug"
      _ew_verbose="--verbose"
      ;;
    *)
      if [ -n "${_ew_default_organization}" ]; then
        _ew_usage="Usage: ${_ew_script_name} [--verbose] [--debug] [DEFAULT-ORGANIZATION]"
        echo "echo \"${_ew_usage}\";"
        echo "${_ew_usage}" >&2
        echo "exit 2"
        exit 2
      else
        _ew_default_organization="$1"
      fi
      ;;
  esac
  shift
done

### Compute the values

# The "set-" script does all the work.  It writes everything but the variable
# values to standard error, so it does not disturb the variable settings that
# this script writes to standard output.
# The command-line argument wins, but an inherited CI_DEFAULT_ORGANIZATION is
# honored if there is no argument, so that the two interfaces agree.
# PLUME_SCRIPTS tells `set-git-range` where to find the script that it sources;
# it is set unconditionally, because it is harmless for a "set-" script that
# does not read it.
# shellcheck disable=SC2034,SC2154
PLUME_SCRIPTS="${_ew_script_dir}"
CI_DEFAULT_ORGANIZATION="${_ew_default_organization:-${CI_DEFAULT_ORGANIZATION}}"
# shellcheck disable=SC2034
CI_VERBOSE="${_ew_verbose}"
# shellcheck disable=SC2034
CI_DEBUG="${_ew_debug}"
# `.` on a file that does not exist is an error in a special builtin, so the
# shell would abort here, without reaching the `exit` below and without
# writing anything on standard output.  The client's `eval` would then succeed
# with no values.  See the same check in the client.
# shellcheck disable=SC2154
if [ ! -r "${_ew_script_dir}/${_ew_helper}" ]; then
  echo "exit 2"
  echo "${_ew_script_name}: cannot read ${_ew_script_dir}/${_ew_helper}" >&2
  exit 2
fi
# The file name is computed, so shellcheck cannot check the sourced file from
# here; it checks each "set-" script on its own.
# shellcheck source=/dev/null
# shellcheck disable=SC2154
. "${_ew_script_dir}/${_ew_helper}"
_ew_status=$?
if [ "${_ew_status}" -ne 0 ]; then
  # The client's `eval` reports the status of the text it evaluated, not of
  # this script, so exiting silently would leave the client with status 0 and
  # with no value (or a stale value) for each variable.  Writing `exit` on
  # standard output makes the client fail.  The "set-" script already reported
  # the reason on standard error.
  echo "exit ${_ew_status}"
  exit "${_ew_status}"
fi

### Print it out

# ${_ew_variables} is unquoted on purpose, so that the shell splits it into
# variable names.
# shellcheck disable=SC2086,SC2154
for _ew_variable in ${_ew_variables}; do
  eval "_ew_value=\${${_ew_variable}}"
  # shellcheck disable=SC2154
  echo "${_ew_variable}=$(_ew_shell_quote "${_ew_value}"); export ${_ew_variable};"
done
