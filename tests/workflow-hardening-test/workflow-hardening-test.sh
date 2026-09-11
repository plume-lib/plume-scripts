#!/bin/sh

# Tests that every GitHub Actions workflow in this repository is hardened.
#
# A workflow runs with a token and with read access to the repository's
# secrets, so anything it executes runs with them.  The checks below are the
# ones whose absence has bitten this repository:
#
#  * Code fetched from a mutable ref -- a branch rather than a tag or a commit
#    -- is whatever that ref says at the moment of the fetch, not what was
#    reviewed.  Piping such a fetch into a shell executes it, and doing so
#    under `sudo` executes it as root.
#  * Without a `permissions:` block, a workflow gets the repository's default
#    token permissions, which may be read-write.
#  * `actions/checkout` leaves the token in `.git/config` unless
#    `persist-credentials: false`, so any later step -- including one from a
#    third-party action -- can read it and push with it.
#  * A full-history checkout is both slow and more than these workflows use;
#    `fetch-depth: 1` says so explicitly rather than by default.
#
# These are textual checks on the workflow files.  That is coarse, but it is
# what makes them apply to workflows added later:  a new workflow is covered
# the moment it is added, with nothing to register here.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PLUME_SCRIPTS="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
WORKFLOW_DIR="${PLUME_SCRIPTS}/.github/workflows"

status=0

# fail FILE MESSAGE: reports that FILE violates MESSAGE.
fail() {
  echo "FAIL: $(basename -- "$1"): $2"
  status=1
}

# pass FILE MESSAGE: reports that FILE satisfies MESSAGE.
pass() {
  echo "PASS: $(basename -- "$1"): $2"
}

# A workflow file, not the directory's README.
for workflow in "$WORKFLOW_DIR"/*.yaml "$WORKFLOW_DIR"/*.yml; do
  [ -f "$workflow" ] || continue

  ### Remote code

  # `curl ... | sh`, with or without `sudo`, and the `wget -O- ...` spelling of
  # the same thing.  The fetched text is executed, so it must not be fetched at
  # all in a workflow:  pinning it would not make the pipe reviewable, and this
  # repository's workflows have no need for one.
  if grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)*(ba|da|z)?sh\b' \
    "$workflow"; then
    fail "$workflow" "pipes a downloaded file into a shell"
  else
    pass "$workflow" "does not pipe a downloaded file into a shell"
  fi

  # A download from a branch of a repository, which is a moving target.  A tag
  # or a commit SHA in the URL is fine.
  if grep -Eq 'https?://[^ "'"'"']*/(main|master)/' "$workflow"; then
    fail "$workflow" "downloads from a mutable branch rather than a pinned ref"
  else
    pass "$workflow" "downloads only from pinned refs"
  fi

  # Third-party actions must be pinned too; `uses: owner/action@main` has the
  # same problem as a URL naming a branch.
  if grep -Eq '^[[:space:]-]+uses:[[:space:]]*[^ ]+@(main|master)[[:space:]]*$' \
    "$workflow"; then
    fail "$workflow" "uses an action pinned to a mutable branch"
  else
    pass "$workflow" "uses only actions pinned to a tag or SHA"
  fi

  ### Token exposure

  # A `permissions:` block, at the top level or in every job.  Checking only
  # for its presence, rather than for particular permissions, keeps this from
  # objecting to a workflow that legitimately needs to write.
  if grep -Eq '^[[:space:]]*permissions:' "$workflow"; then
    pass "$workflow" "declares permissions"
  else
    fail "$workflow" "does not declare permissions"
  fi

  # Checkout hardening, for the workflows that check out at all.
  if grep -Eq 'uses:[[:space:]]*actions/checkout@' "$workflow"; then
    for setting in persist-credentials:.*false fetch-depth:; do
      if grep -Eq "^[[:space:]]*${setting}" "$workflow"; then
        pass "$workflow" "sets ${setting%%:*} on checkout"
      else
        fail "$workflow" "checks out without ${setting%%:*}"
      fi
    done
  fi
done

exit "$status"
