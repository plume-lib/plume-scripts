# An example input for `workflow-hardening-test.sh`:  a file that is not a
# workflow, or that is one whose jobs the checks did not find.  Reporting
# nothing about it would be indistinguishable from reporting that it is
# hardened, when in fact the per-job checks examined nothing.

name: No jobs

"on": [push]

permissions:
  contents: read
