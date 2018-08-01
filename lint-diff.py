#!/usr/bin/env python

# Filter the output of lint, to only show output for changed lines.
#
# This is useful when you want to enforce some style guideline, but
# making the changes globally in your project would be too burdensome.
# You can make the requirement only for new and and lines, so your
# codebase will conform to the new standard gradually, as you edit it.

# Usage:  lint-diff.py [options] diff.txt [lint-output.txt]
#         If lint-output is omitted, use standard input.
# Output: all lines in lint-output that are on a changed line
#         Output status is 1 if it produced any output, 0 if not, 2 if error.
# Options: --strip-diff=N means to ignore N leading "/" in diff.txt.
#          --strip-lint=N means to ignore N leading "/" in lint-output.txt.
#              Affects matching, but not output, of lines.

# Here is how you could use this in Travis require that pull requests
# satisfy the command `command-that-issues-warnings`:
#
# (git diff "${TRAVIS_COMMIT_RANGE/.../..}" > /tmp/diff.txt 2>&1) || true
# (command-that-issues-warnings > /tmp/warnings.txt 2>&1) || true
# [ -s /tmp/diff.txt ] || (echo "/tmp/diff.txt is empty" && false)
# wget https://raw.githubusercontent.com/plume-lib/plume-scripts/master/lint-diff.py
# python lint-diff.py --strip-diff=1 --strip-lint=2 /tmp/diff.txt /tmp/warnings.txt


# Implementation notes:
# 1. It may be possible to achieve a similar result using diff (but not `git diff`):
# https://unix.stackexchange.com/questions/34874/diff-output-line-numbers .
# 2. The documentation for diffFilter (https://github.com/exussum12/coverageChecker)
# suggests it has this same functionality, but my tests indicate it does not.


from __future__ import print_function

import os
import re
import sys

strip_diff = 0
strip_lint = 0


def eprint(*args, **kwargs):
    """Print to stderr."""
    print(*args, file=sys.stderr, **kwargs)

def strip_dirs(filename, num_dirs):
    """Strip off `num_dirs` leading "/" characters."""
    if num_dirs == 0:
        return filename
    else:
        return os.path.join(*(filename.split(os.path.sep)[num_dirs:]))
## Tests:
"""
import os
assert strip_dirs("/a/b/c/d", 0) == '/a/b/c/d'
assert strip_dirs("/a/b/c/d", 1) == 'a/b/c/d'
assert strip_dirs("/a/b/c/d", 2) == 'b/c/d'
assert strip_dirs("/a/b/c/d", 3) == 'c/d'
assert strip_dirs("/a/b/c/d", 4) == 'd'
assert strip_dirs("/a/b/c/", 0) == '/a/b/c/'
assert strip_dirs("/a/b/c/", 1) == 'a/b/c/'
assert strip_dirs("/a/b/c/", 2) == 'b/c/'
assert strip_dirs("/a/b/c/", 3) == 'c/'
assert strip_dirs("/a/b/c/", 4) == ''
"""


### Main routine

# True if the diff filenames start with "a/" and "b/".
relative_diff = False
# True if a warning has been issued about relative directories.
relative_diff_warned = False

# TODO: Use argparse instead?  I don't see how to indicate that
# the lint-output.txt argument is optional.
while len(sys.argv) > 1 and sys.argv[1].startswith("--strip-"):
    m = re.match('^--strip-diff=([0-9]+)$', sys.argv[1])
    if m:
        strip_diff = int(m.group(1))
        del sys.argv[1]
        continue
    m = re.match('^--strip-lint=([0-9]+)$', sys.argv[1])
    if m:
        strip_lint = int(m.group(1))
        del sys.argv[1]
        continue
    eprint("Bad argument:", sys.argv[1])
    sys.exit(2)

if len(sys.argv) != 2 and len(sys.argv) != 3:
    eprint(sys.argv[0], "needs 1 or 2 arguments, got", len(sys.argv)-1)
    sys.exit(2)

# A dictionary from file names to a set of ints
changed = {}

# 1 if this produced any output, 0 if not
status = 0

diff_filename = sys.argv[1]
with open(diff_filename) as diff:
    ppp_re = re.compile('\+\+\+ (\S*).*')
    atat_re = re.compile('@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*')
    content_re = re.compile('[ +-].*')

    filename=''
    lineno=-1000000
    for diff_line in diff:
        if diff_line.startswith("---"):
            continue
        m = ppp_re.match(diff_line)
        if m:
            if m.group(1).startswith("b/"): # heuristic
                relative_diff = True
            try:
                filename = strip_dirs(m.group(1), strip_diff)
            except TypeError:
                filename = "diff filename above common directory"
                ## It's not an error; it just means this file doesn't appear in lint output.
                # eprint('Bad --strip-diff={0} ; line has fewer "/": {1}'.format(strip_diff, m.group(1)))
                # sys.exit(2)
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

if relative_diff and strip_diff == 0:
    eprint("warning:", sys.argv[1], "may use relative paths but --strip-diff=0")    

if len(sys.argv) == 3:
    lint_filename = sys.argv[2]
    lint = open(lint_filename)
else:
    lint_filename = "stdin"
    lint = sys.stdin

filename_lineno_re = re.compile('([^:]*):([0-9]+):.*')

for lint_line in lint:
    m = filename_lineno_re.match(lint_line)
    if m:
        try:
            filename = strip_dirs(m.group(1), strip_lint)
        except TypeError:
            filename = "lint filename above common directory"
            ## It's not an error; it just means this file doesn't appear in lint output.
            # eprint('Bad --strip-lint={0} ; line has fewer "/": {1}'.format(strip_lint, m.group(1)))
            # sys.exit(2)
        if filename.startswith("/") and relative_diff and strip_lint == 0:
            if not relative_diff_warned:
                eprint("warning:", sys.argv[1], "uses relative paths but", lint_filename, "uses absolute paths")
                relative_diff_warned = True
        lineno = int(m.group(2))
        if (filename in changed and lineno in changed[filename]):
            print(lint_line, end='')
            status = 1

if lint is not sys.stdin:
    lint.close

sys.exit(status)
