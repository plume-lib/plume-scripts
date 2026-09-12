# An example input for `workflow-hardening-test.sh`:  a workflow that fetches
# code and runs it, in the spellings that a file-wide grep for `| sh` misses,
# and that names actions by mutable refs, in the spellings that a grep for
# `@main` at the end of a line misses.

name: Fetch and run

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
      - name: A pipe split across two lines
        run: |
          curl -fLSs https://example.com/main/install.sh \
            | sudo bash
      - name: A pipe into a shell run by sudo with options
        run: curl -fLSs https://example.com/install.sh | sudo -E bash
      - name: A pipe with an intervening stage
        run: curl -fLSs https://example.com/install.sh | tr -d "\r" | sh
      - name: A download in one step and a shell in another
        run: wget -q -O install.sh https://example.com/install.sh
      - name: Run the downloaded file
        run: sudo bash install.sh
      - uses: example/action@main # pinned later
      - uses: example/other@develop
      - uses: example/unversioned
