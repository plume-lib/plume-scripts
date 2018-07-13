#!/usr/bin/env python

# Filter the ouput of lint, to only show output for changed lines.

# Usage:  lint-diff.py diff.txt [lint-output.txt]
#         If lint-output is omitted, use standard input.
# Output: all lines in lint-output that are on a changed line
#         Output status is 1 if it produced any output, 0 if not, 2 if error.

# The documentation for diffFilter (https://github.com/exussum12/coverageChecker)
# suggests it has this same functionality, but my tests indicate it does not.

# It may be possible to achieve a similar result using diff (but not `git diff`):
# https://unix.stackexchange.com/questions/34874/diff-output-line-numbers

from __future__ import print_function

import re
import sys

def eprint(*args, **kwargs):
    """Print to stderr."""
    print(*args, file=sys.stderr, **kwargs)

if len(sys.argv) != 2 and len(sys.argv) != 3:
    eprint(sys.argv[0], " needs 1 or 2 arguments, got ", len(sys.argv)-1)
    sys.exit(2)

# A dictionary from file names to a set of ints
changed = {}

# 1 if this produced any output, 0 if not
status = 0

with open(sys.argv[1]) as diff:
    ppp_re = re.compile('\+\+\+ (b/)?(\S*).*')
    atat_re = re.compile('@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*')
    content_re = re.compile('[ +-].*')

    filename=''
    lineno=-1000000
    for diff_line in diff:
        if diff_line.startswith("---"):
            continue
        m = ppp_re.match(diff_line)
        if m:
            filename = m.group(2)
            if filename not in changed:
                changed[filename] = set()
            continue
        m = atat_re.match(diff_line)
        if m:
            lineno = int(m.group(3))
            continue
        if diff_line.startswith("+"):
            changed[filename].add(lineno)
            lineno += 1
        if diff_line.startswith(" "):
            lineno += 1
        if diff_line.startswith("-"):
            continue

if len(sys.argv) == 3:
    lint = open(sys.argv[2])
else:
    lint = sys.stdin

filename_lineno_re = re.compile('([^:]*):([0-9]+):.*')

for lint_line in lint:
    m = filename_lineno_re.match(lint_line)
    if m:
        filename = m.group(1)
        lineno = int(m.group(2))
        if (filename in changed and lineno in changed[filename]):
            print(lint_line, end='')
            status = 1

if lint is not sys.stdin:
    lint.close

sys.exit(status)
