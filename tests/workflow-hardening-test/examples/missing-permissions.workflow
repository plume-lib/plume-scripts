# An example input for `workflow-hardening-test.sh`:  a workflow with no
# top-level `permissions:` and with one job that declares none.  A job-level
# block covers only its own job, so the check is per job rather than per file.

name: Missing permissions

"on": [push]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 1
          persist-credentials: false
      - run: make
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 1
          persist-credentials: false
      - run: make test
