#!/bin/sh

# Tests that `set-ci-org-and-branch` notices the HTTP status of a failed
# GitHub API request and reports which status it was.
#
# The script used to fetch the pull request with `curl -s` or `wget -q` and
# look only at what `jq` found in the result.  `curl -s` exits 0 on an error
# response, printing the server's error body, and `wget -q` prints the same
# exit status for every error response.  So "403, the request was throttled" --
# which succeeds if the job is re-run later -- was indistinguishable from
# "404, there is no such pull request", which never will be; and the request
# that determines CI_BRANCH for a GitHub Actions job whose ref is like
# "42/merge" failed with no message at all.
#
# The requests go to a local HTTP server that answers with the status named by
# the pull request number, so this test needs no network and no throttling.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

# The script and this test need these, and skipping is better than failing:  a
# missing prerequisite is not a defect in the script.
for prerequisite in jq python3 curl; do
  if [ -z "$(command -v "$prerequisite" 2> /dev/null)" ]; then
    echo "$(basename -- "$0"): skipping, because ${prerequisite} is not installed."
    exit 0
  fi
done

work="$(mktemp -d)"
server_pid=""
# shellcheck disable=SC2064  # $work is expanded now on purpose.
trap 'if [ -n "$server_pid" ]; then kill "$server_pid" 2> /dev/null; fi; rm -rf "'"$work"'"' EXIT HUP INT TERM

### A stand-in for the GitHub API.
#
# It answers a request for pull request NNN with HTTP status NNN, so that a
# test case chooses the status by choosing the pull request number.  Status 200
# gets a pull request description whose head repository differs from this
# clone's, so that a case can tell an answer that came from the response apart
# from one that came from a fallback.

cat > "$work/server.py" << 'EOF'
"""An HTTP server that answers a request for pull request NNN with status NNN."""

import http.server
import json

PULL_REQUEST = {
    "head": {
        "ref": "feature",
        "label": "headorg:feature",
        "repo": {"owner": {"login": "headorg"}},
    }
}
ERROR = {
    "message": "API rate limit exceeded",
    "documentation_url": "https://docs.github.com/rest",
}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802  # The name is http.server's.
        try:
            status = int(self.path.rstrip("/").rsplit("/", 1)[-1])
        except ValueError:
            status = 500
        body = json.dumps(PULL_REQUEST if status == 200 else ERROR).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        """Say nothing; the test's output is the only output that matters."""


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
EOF

python3 "$work/server.py" > "$work/port" &
server_pid=$!
port=""
ready=""
# The server picks its own port, so that concurrent runs of this test do not
# collide; wait for it to say which one, and then until it answers.  A case
# that ran before the server was listening would look like the failure that
# this test is about.
waited=0
while [ -z "$ready" ] && [ "$waited" -lt 100 ]; do
  # The server may not have written the file yet; that is what this loop is
  # for, so a missing file must not abort the test under `set -e`.
  port="$(cat "$work/port" 2> /dev/null || true)"
  if [ -n "$port" ] \
    && curl -s -o /dev/null --max-time 10 "http://127.0.0.1:${port}/200"; then
    ready="true"
  else
    sleep 0.1
    waited=$((waited + 1))
  fi
done
if [ -z "$ready" ]; then
  echo "FAIL: the test's HTTP server did not start"
  exit 1
fi

### Stand-ins for curl and wget that send api.github.com requests to that
### server.  They rewrite only the URL, so that the script's real command line
### -- its timeouts, its `--write-out`, its `-S` -- is what the real curl and
### the real wget receive.

mkdir "$work/bin"
for tool in curl wget; do
  real_tool="$(command -v "$tool" 2> /dev/null)" || real_tool=""
  if [ -z "$real_tool" ]; then
    continue
  fi
  cat > "$work/bin/$tool" << EOF
#!/bin/sh
# Runs ${real_tool} with api.github.com replaced by this test's HTTP server.
remaining=\$#
while [ "\$remaining" -gt 0 ]; do
  arg="\$1"
  shift
  case "\$arg" in
    https://api.github.com/*) arg="http://127.0.0.1:${port}/\${arg#https://api.github.com/}" ;;
  esac
  set -- "\$@" "\$arg"
  remaining=\$((remaining - 1))
done
exec ${real_tool} "\$@"
EOF
  chmod +x "$work/bin/$tool"
done

### A PATH that contains wget but not curl, for the cases that test the wget
### code path.  The script prefers curl when both are installed, so the only
### way to reach that path is a PATH without curl -- which means listing the
### commands that the script uses.

mkdir "$work/bin-wget"
ln -s "$work/bin/wget" "$work/bin-wget/wget"
for command_name in git jq awk head tr sort grep cut sed cat sh; do
  command_path="$(command -v "$command_name" 2> /dev/null)" || command_path=""
  if [ -n "$command_path" ]; then
    ln -s "$command_path" "$work/bin-wget/$command_name"
  fi
done
wget_path_works="true"
# The inner script is single-quoted on purpose:  it is run under another PATH,
# so its `command -v` must run there rather than being expanded here.
# shellcheck disable=SC2016
if ! env -i PATH="$work/bin-wget" HOME="$HOME" sh -c '
  for command_name in git jq awk head tr sort grep cut wget; do
    command -v "$command_name" > /dev/null || exit 1
  done
  # The point of this PATH is that the script cannot find curl on it.
  if command -v curl > /dev/null; then exit 1; fi
  git --version > /dev/null
' 2> /dev/null; then
  wget_path_works=""
fi

### A repository that looks like a GitHub Actions checkout.  Its origin is
### local, so that this test does not need the network.

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email test@example.com
git config user.name "Test User"
echo one > file.txt
git add file.txt
git commit -q -m "First commit"
git clone -q --bare . "$work/origin.git"
git remote add origin "$work/origin.git"
git fetch -q origin
git remote set-head origin main
SHA="$(git rev-parse HEAD)"

### The test

status=0

# run PATH REF-NAME HEAD-REF EVENT-NAME [EVENT-PATH]: sources the script the
# way its documentation says to, in a simulated GitHub Actions job, leaving
# CI_ORGANIZATION and CI_BRANCH in "$work/values" and the script's diagnostics
# in "$work/stderr".  An empty HEAD-REF makes the job not a pull request.
# EVENT-PATH is the job's event payload file; the default is no such file.
run() {
  run_path="$1"
  ref_name="$2"
  head_ref="$3"
  event_name="$4"
  event_path="${5-}"
  # A run that fails before writing the file must not be judged on the previous
  # run's values.
  rm -f "$work/values"
  # Run with an empty environment except for the GitHub Actions variables, so
  # that this test behaves the same whether or not it is itself running under
  # CI:  another CI service's variables would send the script down another code
  # path.
  # The inner script is single-quoted on purpose:  its arguments are passed
  # positionally, so that this shell does not expand them into it.
  # shellcheck disable=SC2016
  env -i PATH="$run_path" HOME="$HOME" \
    GITHUB_ACTIONS=true GITHUB_EVENT_NAME="$event_name" \
    GITHUB_HEAD_REF="$head_ref" GITHUB_BASE_REF=main \
    GITHUB_REF_NAME="$ref_name" GITHUB_REPOSITORY=testorg/testrepo \
    GITHUB_SHA="$SHA" GITHUB_EVENT_PATH="$event_path" \
    sh -c '
      cd "$1" || exit 2
      CI_DEFAULT_ORGANIZATION=testorg
      . "$2/set-ci-org-and-branch" || exit 2
      printf "%s\n%s\n" "$CI_ORGANIZATION" "$CI_BRANCH" > "$3/values"
    ' sh "$work/repo" "$PLUME_SCRIPTS" "$work" 2> "$work/stderr"
}

# report DESCRIPTION OK: reports the result of one check.
report() {
  if [ -n "$2" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    echo "---- start of the script's standard error ----"
    cat "$work/stderr"
    echo "---- end of the script's standard error ----"
    status=1
  fi
}

# check_status TOOL PATH STATUS: checks that a GitHub Actions pull request job
# whose API request gets HTTP status STATUS reports that status, and does not
# report a different one.  The pull request number is the status, because this
# test's server answers a request for pull request NNN with status NNN.
check_status() {
  tool="$1"
  check_path="$2"
  http_status="$3"
  run "$check_path" "${http_status}/merge" feature pull_request || true
  ok=""
  if grep -q "HTTP ${http_status}" "$work/stderr"; then
    ok="true"
    # A message that named every status would pass the check above while
    # telling the reader nothing.
    for other_status in 403 404 500; do
      if [ "$other_status" != "$http_status" ] \
        && grep -q "HTTP ${other_status}" "$work/stderr"; then
        ok=""
      fi
    done
  fi
  report "$tool: a pull request job reports HTTP ${http_status}" "$ok"
}

# check_success TOOL PATH: checks that a request that succeeds is still
# understood -- that reading the status did not cost the body.
check_success() {
  tool="$1"
  check_path="$2"
  if ! run "$check_path" 200/merge feature pull_request; then
    report "$tool: a pull request job with a good response exits with status 0" ""
    return
  fi
  organization="$(sed -n 1p "$work/values")"
  branch="$(sed -n 2p "$work/values")"
  ok="true"
  if [ "$organization" != "headorg" ] || [ "$branch" != "feature" ]; then
    ok=""
  fi
  # The pull request was found, so there is nothing to warn about.
  if grep -q "warning" "$work/stderr"; then
    ok=""
  fi
  report "$tool: a good response yields CI_ORGANIZATION=headorg and CI_BRANCH=feature (got '${organization}' and '${branch}')" "$ok"
}

# check_branch_path TOOL PATH: checks the request that determines CI_BRANCH for
# a GitHub Actions job that is not a pull request but whose ref is like
# "42/merge".  That request's failure used to be entirely silent:  no caller
# warned about it, and the script returned 0 with an empty CI_BRANCH, which a
# client would use as if it were a branch name.
check_branch_path() {
  tool="$1"
  check_path="$2"
  exit_status=0
  run "$check_path" 403/merge "" push || exit_status=$?
  ok=""
  if grep -q "HTTP 403" "$work/stderr" && [ "$exit_status" -ne 0 ]; then
    ok="true"
  fi
  report "$tool: a job with a merge ref reports HTTP 403 and fails (exit status ${exit_status})" "$ok"
}

# check_branch_event TOOL PATH: checks that when that request fails, the branch
# is taken from the job's event payload, which describes the same pull request.
check_branch_event() {
  tool="$1"
  check_path="$2"
  cat > "$work/event.json" << 'EOF'
{"pull_request": {"head": {"ref": "feature-from-event"}}}
EOF
  ok=""
  if run "$check_path" 403/merge "" push "$work/event.json"; then
    branch="$(sed -n 2p "$work/values")"
    if [ "$branch" = "feature-from-event" ]; then
      ok="true"
    fi
  else
    branch="<the script failed>"
  fi
  report "$tool: a job with a merge ref falls back to the event payload (got '${branch}')" "$ok"
}

check_success curl "$work/bin:$PATH"
check_status curl "$work/bin:$PATH" 403
check_status curl "$work/bin:$PATH" 404
check_branch_path curl "$work/bin:$PATH"
check_branch_event curl "$work/bin:$PATH"

if [ -n "$wget_path_works" ]; then
  check_success wget "$work/bin-wget"
  check_status wget "$work/bin-wget" 403
  check_status wget "$work/bin-wget" 404
  check_branch_path wget "$work/bin-wget"
  check_branch_event wget "$work/bin-wget"
else
  echo "$(basename -- "$0"): skipping the wget cases, because this system has no PATH that contains wget, and the commands the script needs, but not curl."
fi

exit "$status"
