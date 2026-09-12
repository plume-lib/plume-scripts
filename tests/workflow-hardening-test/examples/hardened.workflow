# An example input for `workflow-hardening-test.sh`:  a workflow that violates
# nothing.  The constructs named in these comments are forbidden, and a check
# that did not ignore comments would report this file for naming them:
#   curl -fLSs https://example.com/main/install.sh | sudo bash
#   uses: example/action@main

name: Hardened

"on": [push, pull_request]

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
      # Downloading is permitted; running what was downloaded is not.  The
      # checksum is what makes the download reviewable.
      - name: Install a pinned release
        run: |
          set -eu
          curl -fLSs -o tool.tar.gz "https://example.com/tool/releases/download/v1.2.3/tool.tar.gz"
          echo "0123456789abcdef  tool.tar.gz" | sha256sum --check --strict -
          tar --extract --gzip --file tool.tar.gz tool
          install -m 755 tool "$HOME/.local/bin/tool"
      - uses: example/action@v1.2.3
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 1
          persist-credentials: false
      - run: make test
