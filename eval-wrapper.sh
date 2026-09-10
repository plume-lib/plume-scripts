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
# does not see those reads.  The tests do check that the variable names here
# agree with the ones that the clients and the "set-" scripts use:  a
# misspelling makes the printed value empty, which `eval-quoting-test` and
# `github-ref-name-test` detect.
# shellcheck disable=SC2034
# shellcheck disable=SC2154

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
PLUME_SCRIPTS="${_ew_script_dir}"
CI_DEFAULT_ORGANIZATION="${_ew_default_organization:-${CI_DEFAULT_ORGANIZATION}}"
CI_VERBOSE="${_ew_verbose}"
CI_DEBUG="${_ew_debug}"
# The file name is computed, so shellcheck cannot check the sourced file from
# here; it checks each "set-" script on its own.
# shellcheck source=/dev/null
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
# shellcheck disable=SC2086
for _ew_variable in ${_ew_variables}; do
  eval "_ew_value=\${${_ew_variable}}"
  echo "${_ew_variable}=$(_ew_shell_quote "${_ew_value}"); export ${_ew_variable};"
done
