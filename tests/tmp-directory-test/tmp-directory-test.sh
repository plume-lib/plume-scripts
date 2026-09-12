#!/bin/sh

# Tests that no file uses or recommends a clone directory that is not per-user,
# such as `/tmp/plume-scripts`.
#
# On a multi-user or shared CI host, whoever creates `/tmp/plume-scripts` first
# owns it, and every other user then sources and executes whatever it contains.
# So the install snippets, in the README and at the top of each script, must
# name a per-user directory -- and must still do so when USER is unset, as it is
# under cron and under some CI runners -- and so must `set-git-range`'s default
# for PLUME_SCRIPTS.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  status=1
}

# An `id` that names a user whose /tmp directory does not exist, and an `id`
# that fails.  The checks below run with USER unset, and without these the
# expected directory would be the current user's -- which may exist, because it
# is where the README installs, and then `set-git-range` would find the scripts
# and make network requests instead of printing the message being checked.
fake_user="plume-scripts-test-id"
mkdir "${work}/bin" "${work}/bin-failing-id"
printf '#!/bin/sh\necho %s\n' "${fake_user}" > "${work}/bin/id"
printf '#!/bin/sh\nexit 1\n' > "${work}/bin-failing-id/id"
chmod +x "${work}/bin/id" "${work}/bin-failing-id/id"

### Every file names only per-user /tmp directories.

# Check every file that Git tracks, rather than a list of file names that would
# go stale as files are added and as install snippets move among them.  Skip
# this directory, whose text is these very patterns.
git -C "${PLUME_SCRIPTS}" ls-files -- ':!tests/tmp-directory-test/' \
  > "${work}/files"
if [ ! -s "${work}/files" ]; then
  fail "cannot list the files that Git tracks in ${PLUME_SCRIPTS}"
fi

# `/tmp/$USER` and `/tmp/${USER}` are forbidden along with `/tmp/plume-scripts`
# itself, because USER is unset under cron and under some CI runners; they then
# name `/tmp//plume-scripts`, which is `/tmp/plume-scripts`.
# The `\$` are grep's, not the shell's.
# shellcheck disable=SC2016
shared_tmp='/tmp/plume-scripts|/tmp/\$USER|/tmp/\$\{USER\}'
shared_tmp="${shared_tmp}"'|git -C /tmp( |$)|mkdir -p /tmp( |$)'

found_shared_tmp=0
while IFS= read -r file; do
  matches="$(grep -n -E "${shared_tmp}" "${PLUME_SCRIPTS}/${file}" || true)"
  if [ -n "${matches}" ]; then
    fail "${file} names a /tmp directory that is not per-user:"
    echo "${matches}" | sed 's/^/  /'
    found_shared_tmp=1
  fi
done < "${work}/files"
if [ "${found_shared_tmp}" -eq 0 ]; then
  pass "no file names a /tmp directory that is not per-user"
fi

### Each install snippet's directory is per-user even when USER is unset.

# Evaluate the snippets' assignments to PLUME_SCRIPTS rather than only
# pattern-matching them:  what matters is the directory that a client who
# copies a snippet actually gets.
git -C "${PLUME_SCRIPTS}" grep -h -o -E \
  -e 'PLUME_SCRIPTS="/tmp[^"]*"' -e 'PLUME_SCRIPTS=/tmp[^"[:space:]]*' \
  -- ':!tests/tmp-directory-test/' | sort -u > "${work}/assignments"
if [ ! -s "${work}/assignments" ]; then
  fail "no file sets PLUME_SCRIPTS to a /tmp directory; are the snippets gone?"
fi

while IFS= read -r assignment; do
  # shellcheck disable=SC2016
  value="$(env -i PATH="${work}/bin:${PATH}" sh -c \
    "${assignment}"'; printf %s "${PLUME_SCRIPTS}"' 2>&1 || true)"
  if [ "${value}" = "/tmp/${fake_user}/plume-scripts" ]; then
    pass "\`${assignment}\` is per-user when USER is unset"
  else
    fail "\`${assignment}\` yields \"${value}\" when USER is unset"
  fi
done < "${work}/assignments"

### `set-git-range`'s default for PLUME_SCRIPTS.

# The default is visible only in the message that `set-git-range` prints when
# it cannot find `set-ci-org-and-branch`, so check that message.  A client that
# installed where the README says, and that did not set PLUME_SCRIPTS, must be
# sent to its own directory.
#
# Run with an empty environment, both so that a CI variable of this test's own
# cannot send the script down another code path and so that USER is unset
# except where the caller sets it.  Run under `set -e`, because a client that
# uses `set -e` must see the message rather than a shell that exits silently.
check_default() {
  description="$1"
  expected="$2"
  shift 2
  # shellcheck disable=SC2016
  actual="$(env -i HOME="${HOME}" "$@" sh -c '
    set -e
    . "$1"/set-git-range
  ' sh "${PLUME_SCRIPTS}" 2>&1 || true)"
  case "${actual}" in
    *"${expected}"*)
      pass "set-git-range, ${description}: says ${expected}"
      ;;
    *)
      fail "set-git-range, ${description}: does not say ${expected}"
      echo "  output: ${actual}"
      ;;
  esac
  # The patterns end in "/" or double the slash, so that a per-user directory
  # whose user name happens to start with "plume-scripts" does not match.
  case "${actual}" in
    *"/tmp/plume-scripts/"* | *"/tmp//plume-scripts"*)
      fail "set-git-range, ${description}: names a shared /tmp directory"
      echo "  output: ${actual}"
      ;;
  esac
}

check_default "USER set" \
  "/tmp/plume-scripts-test-user/plume-scripts/set-ci-org-and-branch" \
  PATH="${PATH}" USER=plume-scripts-test-user

check_default "USER unset" \
  "/tmp/${fake_user}/plume-scripts/set-ci-org-and-branch" \
  PATH="${work}/bin:${PATH}"

# When the user name cannot be determined at all, the script must say so rather
# than fall back to a directory that is not per-user.  The message must appear
# even though the client uses `set -e`:  a failing command substitution in an
# assignment exits the client's shell, which would suppress the message.
check_default "user name unknown" \
  "cannot determine your user name" \
  PATH="${work}/bin-failing-id:${PATH}"

exit "$status"
