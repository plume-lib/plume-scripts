#!/bin/sh

# Tests `gradlew-retry`.  Each case runs `gradlew-retry` in a directory whose `gradlew` is a fake
# that records each run and then succeeds or fails as the case requires.  The cases that involve a
# 404 query Maven Central, so they are skipped if Maven Central is unreachable.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
GRADLEW_RETRY="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/gradlew-retry"

# Retry without waiting.
GRADLEW_RETRY_DELAYS="0 0"
export GRADLEW_RETRY_DELAYS

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

# A Maven Central URL of an artifact that exists, and of one that does not.
CENTRAL=https://repo.maven.apache.org/maven2
EXISTING=org/apache/commons/commons-lang3/3.17.0/commons-lang3-3.17.0.pom
NONEXISTENT=org/apache/commons/commons-lang3/0.0.0-no-such-version/commons-lang3-0.0.0-no-such-version.pom

# make_gradlew BODY: makes ./gradlew a script that records the run in file `runs` and then runs
# BODY, a shell command.  Within BODY, $run is the number of this run, starting at 1.
make_gradlew() {
  rm -f "$work/runs"
  cat > "$work/gradlew" << EOF
#!/bin/sh
echo run >> runs
run=\$(wc -l < runs)
$1
EOF
  chmod +x "$work/gradlew"
}

# not_found_output PATH: prints Gradle's output when it finds a module at neither Maven Central
# nor the Gradle Plugin Portal, given the path of the module's pom file within each repository.
not_found_output() {
  cat << EOF
FAILURE: Build failed with an exception.
> Could not resolve all artifacts for configuration 'classpath'.
   > Could not find org.example:example:1.0.
     Searched in the following locations:
       - $CENTRAL/$1
       - https://plugins.gradle.org/m2/$1
EOF
}

# check DESCRIPTION EXPECTED-STATUS EXPECTED-RUNS: runs `gradlew-retry build` in the work directory
# and reports whether its exit status and the number of runs of ./gradlew are as expected.
check() {
  actual_status=0
  (cd "$work" && "$GRADLEW_RETRY" build > output 2>&1) || actual_status=$?
  actual_runs=$(wc -l < "$work/runs" | tr -d ' ')
  if [ "$actual_status" = "$2" ] && [ "$actual_runs" = "$3" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    echo "  expected: status $2, $3 runs"
    echo "  actual:   status $actual_status, $actual_runs runs"
    sed 's/^/  | /' "$work/output"
    status=1
  fi
}

make_gradlew 'exit 0'
check "success is not retried" 0 1

make_gradlew 'echo "FAILURE: Build failed with an exception."; exit 7'
check "a failure other than resolution is not retried, and its status is kept" 7 1

make_gradlew 'echo "> Could not resolve all files for configuration x."
echo "   > Could not GET '\''https://example.org/x.pom'\''. Received status code 502"; exit 1'
check "a 5xx status is retried twice" 1 3

make_gradlew 'echo "Plugin [id: '\''org.example'\'', version: '\''1.0'\''] was not found"; exit 1'
check "a missing plugin is retried twice" 1 3

if ! curl --silent --fail --head --max-time 20 --output /dev/null "$CENTRAL/$EXISTING"; then
  echo "SKIP: gradlew-retry tests of a 404: Maven Central is unreachable"
  exit "$status"
fi

not_found_output "$EXISTING" > "$work/existing.txt"
not_found_output "$NONEXISTENT" > "$work/nonexistent.txt"

# shellcheck disable=SC2016 # The fake ./gradlew, not this script, expands $run.
make_gradlew '[ "$run" -ge 2 ] && exit 0; cat existing.txt; exit 1'
check "a transient 404 is retried until it succeeds" 0 2

make_gradlew 'cat existing.txt; exit 1'
check "a persistent 404 for an existing artifact is retried twice" 1 3

make_gradlew 'cat nonexistent.txt; exit 1'
check "a 404 for a nonexistent artifact is not retried" 1 1

exit "$status"
