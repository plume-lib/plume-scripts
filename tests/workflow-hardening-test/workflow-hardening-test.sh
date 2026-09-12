#!/bin/sh

# Tests that every GitHub Actions workflow in this repository is hardened.
#
# A workflow runs with a token and with read access to the repository's
# secrets, so anything it executes runs with them.  The checks are in
# `workflow-hardening.awk`, which explains each one; they are the ones whose
# absence has bitten this repository.
#
# They are textual checks on the workflow files.  That is coarse, but it is
# what makes them apply to workflows added later:  a new workflow is covered
# the moment it is added, with nothing to register here.
#
# The checks are run twice:  once on the example workflows in `examples/`,
# where the expected output is recorded in a `-goal` file, and once on this
# repository's workflows, which must violate nothing.  Without the examples,
# the second run would say only that no check fired, which is also what it
# would say if the checks were unable to fire at all.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
WORKFLOW_DIR="${PLUME_SCRIPTS}/.github/workflows"
EXAMPLE_DIR="${SCRIPT_DIR}/examples"
CHECKS="${SCRIPT_DIR}/workflow-hardening.awk"

status=0

# check_workflow FILE: writes one "FAIL:" line per hardening violation in
# FILE, or one "PASS:" line if it has none.  Returns 0 if FILE is hardened.
check_workflow() {
  file="$1"
  base="$(basename -- "$file")"
  violations="$(awk -f "$CHECKS" -- "$file")"
  if [ -z "$violations" ]; then
    echo "PASS: ${base}: hardened"
    return 0
  fi
  # A tab separates the line number from the message.
  echo "$violations" | while IFS='	' read -r line message; do
    echo "FAIL: ${base}:${line}: ${message}"
  done
  return 1
}

### The checks themselves, on workflows whose violations are known

# Each example is a workflow that contains one family of violations -- or, for
# `hardened.workflow`, none -- and each `-goal` file is what the checks must
# say about it.  An example is not a workflow of this repository, so it is not
# under `.github/workflows/` and does not end in `.yaml`:  nothing should run
# it, and the tools that lint this repository's workflows should not lint it.
examples=0
for example in "$EXAMPLE_DIR"/*.workflow; do
  [ -f "$example" ] || continue
  examples=$((examples + 1))
  actual="$(check_workflow "$example" || true)"
  if printf '%s\n' "$actual" | diff -u -- "${example}-goal" -; then
    echo "PASS: $(basename -- "$example"): the checks report what they should"
  else
    echo "FAIL: $(basename -- "$example"): the checks do not report what they should"
    status=1
  fi
done

if [ "$examples" -eq 0 ]; then
  echo "FAIL: no examples in ${EXAMPLE_DIR}, so the checks are untested"
  status=1
fi

### This repository's workflows

checked=0
for workflow in "$WORKFLOW_DIR"/*.yaml "$WORKFLOW_DIR"/*.yml; do
  [ -f "$workflow" ] || continue
  checked=$((checked + 1))
  check_workflow "$workflow" || status=1
done

# A test that examines nothing passes, which is the wrong answer:  renaming or
# moving the workflow directory would silently disable every check above.
if [ "$checked" -eq 0 ]; then
  echo "FAIL: no workflows in ${WORKFLOW_DIR}, so nothing was checked"
  status=1
fi

exit "$status"
