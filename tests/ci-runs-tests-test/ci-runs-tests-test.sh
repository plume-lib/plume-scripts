#!/bin/sh

# Tests that a CI service that still runs actually runs the test suite.
#
# The test suite used to be run only by `.travis.yml`, and Travis CI no longer
# builds open-source repositories.  CircleCI ran `prek` and the GitHub Actions
# workflows ran `prek` and `checkbashisms`, so no configuration ran
# `make -C tests`.  The failure is silent:  every CI job passes, and a change
# that breaks a script is reported as green.  (That is how a test suite that
# did not depend on the script under test went unnoticed.)
#
# This test reads the CI configuration rather than the scripts, so it fails
# whenever the test suite is dropped from CI again.  It does not check
# `.travis.yml`, because a Travis CI configuration no longer runs anything.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

cd "$PLUME_SCRIPTS"

status=0

# A shell command that runs the test suite:  `make test` (the top-level
# Makefile's `test` target) or `make -C tests [test]`, with any flags between
# `make` and its arguments.
RUNS_TESTS_RE='(^|[^[:alnum:]_./-])make([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-C[[:space:]]+tests([[:space:]]|$)|test([[:space:]]|$))'

### CircleCI
#
# A job that runs the test suite counts only if some workflow lists it;  a job
# that no workflow mentions never runs.

circleci_config=.circleci/config.yml
if [ ! -f "$circleci_config" ]; then
  echo "SKIP: no $circleci_config"
else
  # The name of each job whose steps run the test suite.
  circleci_jobs="$(awk -v re="$RUNS_TESTS_RE" '
    # The top-level "jobs:" key begins the job definitions, and any other
    # top-level key (such as "workflows:") ends them.
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    /^[^[:space:]#]/ { in_jobs = 0 }
    in_jobs && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
      job = $1
      sub(/:$/, "", job)
      next
    }
    in_jobs && job != "" && $0 ~ re { print job; job = "" }
  ' "$circleci_config")"
  # The "workflows:" section, which is everything from the top-level
  # "workflows:" key to the next top-level key.
  circleci_workflows="$(awk '
    /^workflows:[[:space:]]*$/ { in_workflows = 1; next }
    /^[^[:space:]#]/ { in_workflows = 0 }
    in_workflows { print }
  ' "$circleci_config")"
  circleci_runs_tests=false
  for job in $circleci_jobs; do
    if printf '%s\n' "$circleci_workflows" \
      | grep -Eq "^[[:space:]]*-[[:space:]]+${job}[[:space:]]*:?[[:space:]]*$"; then
      circleci_runs_tests=true
      echo "PASS: CircleCI job \"$job\" runs the test suite"
    else
      echo "FAIL: CircleCI job \"$job\" runs the test suite, but no workflow lists it"
      status=1
    fi
  done
  if [ "$circleci_runs_tests" = false ]; then
    echo "FAIL: no CircleCI job runs the test suite"
    status=1
  fi
fi

### GitHub Actions

github_workflows_dir=.github/workflows
github_runs_tests=false
for workflow in "$github_workflows_dir"/*.yml "$github_workflows_dir"/*.yaml; do
  # The glob is unquoted above, so an unmatched pattern appears literally.
  [ -f "$workflow" ] || continue
  if grep -Eq "$RUNS_TESTS_RE" "$workflow"; then
    github_runs_tests=true
    echo "PASS: GitHub Actions workflow \"$workflow\" runs the test suite"
  fi
done
if [ "$github_runs_tests" = false ]; then
  echo "FAIL: no GitHub Actions workflow runs the test suite"
  status=1
fi

### Travis CI
#
# Travis CI no longer builds open-source repositories, so a `.travis.yml` is
# not CI coverage;  its presence suggests coverage that does not exist.

if [ -e .travis.yml ]; then
  echo "FAIL: .travis.yml exists, but Travis CI no longer builds open-source repositories"
  status=1
else
  echo "PASS: no .travis.yml"
fi

exit "$status"
