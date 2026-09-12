# An example input for `workflow-hardening-test.sh`:  a workflow with one
# hardened checkout and one unhardened one.  Hardening either of them does not
# harden the other, so the check is per step rather than per file.

name: Unhardened checkout

"on": [push]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 1
          persist-credentials: false
      - run: make
      - name: Check out the tests too
        uses: actions/checkout@v7
        with:
          repository: example/tests
          path: tests
      - run: make -C tests test
