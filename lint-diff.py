#!/usr/bin/env python

# Filter the output of lint, to only show output for changed lines.
#
# This is useful when you want to enforce some style guideline, but
# making the changes globally in your project would be too burdensome.
# You can make the requirement only for new and changed lines, so your
# codebase will conform to the new standard gradually, as you edit it.

# Usage:  lint-diff.py [options] diff.txt [lint-output.txt]
#         If lint-output is omitted, use standard input.
# Output: all lines in lint-output that are on a changed line.
#         Output status is 1 if it produced any output, 0 if not, 2 if error.
# Options: --strip-diff=N means to ignore N leading "/" in diff.txt.
#          --strip-lint=N means to ignore N leading "/" in lint-output.txt.
#              Affects matching, but not output, of lines.
#          --guess-strip means guess values for --strip-diff and --strip-lint.
#          --context=N is how many lines adjacent to the changed ones
#              are also considered changed; the default is 2.
#          --debug means to print diagnostic output

# Here is how you could use this in continuous integration (Azure
# Pipelines, CircleCI, and Travis CI are currently supported) to require
# that pull requests satisfy the command `command-that-issues-warnings`:
#
# git -C /tmp/plume-scripts pull > /dev/null 2>&1 \
#   || git -C /tmp clone --depth 1 -q https://github.com/plume-lib/plume-scripts.git
# (command-that-issues-warnings > /tmp/warnings.txt 2>&1) || true
# /tmp/plume-scripts/ci-lint-diff /tmp/warnings.txt


# Implementation notes:
# 1. It may be possible to achieve a similar result using diff (but not `git diff`):
# https://unix.stackexchange.com/questions/34874/diff-output-line-numbers .
# 2. The documentation for diffFilter (https://github.com/exussum12/coverageChecker)
# suggests it has this same functionality, but my tests indicate it does not.


from __future__ import print_function

import os
import re
import sys

DEBUG = False

strip_diff = 0
strip_lint = 0
guess_strip = False

PLUSPLUSPLUS_RE = re.compile(r'\+\+\+ (\S*).*')

FILENAME_LINENO_RE = re.compile('([^:]*):([0-9]+):.*')

MAX_PAIR = (1000, 1000)

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

def min_strips(filename1, filename2):
    """Returns a 2-tuple of 2 integers, indicating the smallest strip values that
make the two filenames equal, or MAX_PAIR if the files have different basenames."""
    components1 = filename1.split(os.path.sep)
    components2 = filename2.split(os.path.sep)
    if components1[-1] != components2[-1]:
        ## TODO: is this special case necessary?
        return MAX_PAIR
    while components1 and components2 and components1[-1] == components2[-1]:
        del components1[-1]
        del components2[-1]
    return (len(components1), len(components2))
## Tests:
"""
import os
assert min_strips("/a/b/c/d", "/a/b/c/d") == (0,0)
assert min_strips("e1/e2/a/b/c/d", "/a/b/c/d") == (2,1)
assert min_strips("/e1/e2/a/b/c/d", "/a/b/c/d") == (3,1)
assert min_strips("e1/e2/a/b/c/d", "a/b/c/d") == (2,0)
assert min_strips("/e1/e2/a/b/c/d", "a/b/c/d") == (3,0)
assert min_strips("/a/b/c/d", "/e/f/g/h") == (0,0)
"""

def pair_min(pair1, pair2):
    """Given two pairs, returns the one that is pointwise lesser.
Fails if neither is lesser."""
    if pair1[0] <= pair2[0] and pair1[1] <= pair2[1]:
        return pair1
    if pair1[0] >= pair2[0] and pair1[1] >= pair2[1]:
        return pair2
    assert False, "incomparable pairs: " + pair1 + " " + pair2
## Tests:
"""
import os
assert pair_min((3,4), (5,6)) == (3,4)
assert pair_min((4,3), (6,5)) == (4,3)
assert pair_min((30,40), (5,6)) == (5,6)
assert pair_min((40,30), (6,5)) == (6,5)
"""

def diff_filenames(diff_filename):
    """All the filenames in the given diff file."""
    result = set()
    with open(diff_filename) as diff:
        for diff_line in diff:
            m = PLUSPLUSPLUS_RE.match(diff_line)
            if m:
                result.add(m.group(1))
    return result

def lint_filenames(lint_filename):
    """All the filenames in the given lint file."""
    result = set()
    with open(lint_filename) as lint:
        for lint_line in lint:
            m = FILENAME_LINENO_RE.match(lint_line)
            if m:
                result.add(m.group(1))
    return result


def guess_strip_filenames(diff_filenames, lint_filenames):
    """Arguments are two lists of file names.
    Result is a pair of integers."""
    result = MAX_PAIR
    for diff_filename in diff_filenames:
        for lint_filename in lint_filenames:
            result = pair_min(result, min_strips(diff_filename, lint_filename))
    return result


def guess_strip_files(diff_file, lint_file):
    """Arguments are files produced by diff and a lint tool, respectively.
    Result is a pair of integers."""
    diff_files = diff_filenames(diff_file)
    lint_files = lint_filenames(lint_file)
    result = guess_strip_filenames(diff_files, lint_files)
    diff_prefix = os.path.commonprefix(diff_files)
    lint_prefix = os.path.commonprefix(lint_files)
    if result[0] > diff_prefix.count("/") or result[1] > lint_prefix.count("/"):
        if DEBUG:
            eprint("lint-diff.py: guess_strip_files giving up: result={} diff_prefix={} lint_prefix={}".format(result, diff_prefix, lint_prefix))
            eprint("diff_files={}".format(diff_files))
            eprint("lint_files={}".format(lint_files))
        return MAX_PAIR
    return result


### Main routine
## TODO: put this into a routine.

# A filename if the diff filenames start with "a/" and "b/", otherwise None.
relative_diff = None
# True if a warning has been issued about relative directories.
relative_diff_warned = False

# This many lines around each changed one are also considered changed
context_lines = 2

# TODO: Use argparse instead?  I don't see how to indicate that
# the lint-output.txt argument is optional.
while len(sys.argv) > 1 and sys.argv[1].startswith("--"):
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
    m = re.match('^--guess-strip$', sys.argv[1])
    if m:
        guess_strip = True
        del sys.argv[1]
        continue
    m = re.match('^--context=([0-9]+)$', sys.argv[1])
    if m:
        context_lines = int(m.group(1))
        del sys.argv[1]
        continue
    m = re.match('^--debug$', sys.argv[1])
    if m:
        DEBUG = True
        del sys.argv[1]
        continue
    eprint("Bad argument:", sys.argv[1])
    sys.exit(2)

if guess_strip and (strip_diff != 0 or strip_lint != 0):
    eprint(sys.argv[0], ": don't supply both --guess-strip and --strip-diff or --strip-lint")
    sys.exit(2)

if len(sys.argv) != 2 and len(sys.argv) != 3:
    eprint(sys.argv[0], "needs 1 or 2 arguments, got", len(sys.argv)-1)
    sys.exit(2)

if guess_strip and len(sys.argv) == 2:
    eprint(sys.argv[0], "needs 2, not 1, file arguments when --guess-strip is provided")
    sys.exit(2)

if guess_strip:
    guessed_strip = guess_strip_files(sys.argv[1], sys.argv[2])
    if guessed_strip == MAX_PAIR:
        if DEBUG:
            eprint("lint-diff.py: --guess-strip failed to guess values")
    else:
        strip_diff = guessed_strip[0]
        strip_lint = guessed_strip[1]
        if DEBUG:
            eprint("lint-diff.py inferred --strip-diff={} --strip-lint={}".format(strip_diff, strip_lint))


# A dictionary from file names to a set of ints (line numbers for changed lines)
changed = {}


diff_filename = sys.argv[1]
with open(diff_filename) as diff:
    atat_re = re.compile('@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*')
    content_re = re.compile('[ +-].*')

    filename = ''
    lineno = -1000000
    for diff_line in diff:
        if diff_line.startswith("---"):
            continue
        m = PLUSPLUSPLUS_RE.match(diff_line)
        if m:
            if m.group(1).startswith("b/"): # heuristic
                relative_diff = diff_line
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
            # Not just the changed line: changed[filename].add(lineno)
            for changed_lineno in range(lineno-context_lines, lineno+context_lines + 1):
                changed[filename].add(changed_lineno)
            lineno += 1
        if diff_line.startswith(" "):
            lineno += 1
        if diff_line.startswith("-"):
            for changed_lineno in range(lineno-context_lines, lineno+context_lines):
                changed[filename].add(changed_lineno)
            continue

if DEBUG:
    for filename in sorted(changed):
        print(filename, sorted(changed[filename]))

if relative_diff is not None and strip_diff == 0:
    $relative_diff =~ s/\s+$//;
    eprint("warning:", sys.argv[1], "may use relative paths (e.g.,", relative_diff, ") but --strip-diff=0", ("(guessed)" if guess_strip else ""))
    if DEBUG:
        eprint("lint-diff.py TODO: add debugging output here")

if len(sys.argv) == 3:
    lint_filename = sys.argv[2]
    lint = open(lint_filename)
else:
    lint_filename = "stdin"
    lint = sys.stdin

# 1 if this produced any output, 0 if not
status = 0

for lint_line in lint:
    m = FILENAME_LINENO_RE.match(lint_line)
    if m:
        try:
            filename = strip_dirs(m.group(1), strip_lint)
        except TypeError:
            filename = "lint filename above common directory"
            ## It's not an error; it just means this file doesn't appear in lint output.
            # eprint('Bad --strip-lint={0} ; line has fewer "/": {1}'.format(strip_lint, m.group(1)))
            # sys.exit(2)
        if filename.startswith("/") and relative_diff is not None and strip_lint == 0:
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
