#!/bin/sh

# Tests that `latex-process-inputs` treats its argument as a file name rather
# than as a Perl 2-argument-`open` mode string.
#
# Perl's 2-argument `open` interprets leading and trailing `>`, `<`, and `|`
# in its argument, and strips surrounding whitespace.  So a `.tex` file whose
# name ends in `|` was run as a command instead of being read, and a file whose
# name starts with a space could not be read at all.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
LPI="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/latex-process-inputs"

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

### A file name that ends in `|` is not run as a command.

# The file is named for the command it would run:  `touch $work/pwned`.
cd "$work"
evil='touch pwned |'
echo 'hello' > "$evil"
# The exit status is not what matters; the side effect is.
"$LPI" --list "$evil" > /dev/null 2>&1 || true
if [ -e "$work/pwned" ]; then
  fail "ran the file name as a command"
else
  pass "did not run the file name as a command"
fi

### A file name that starts with a space is read, not silently trimmed.

# `trimmed.tex` does not exist, so a script that strips the leading space
# fails; one that does not strip it reads the file.
printf 'contents\n' > ' trimmed.tex'
if [ "$("$LPI" ' trimmed.tex' 2> /dev/null)" = "contents" ]; then
  pass "read a file name that starts with a space"
else
  fail "did not read a file name that starts with a space"
fi

### A file name that starts with `>` is read, not opened for writing.

printf 'contents\n' > '>redirect.tex'
if [ "$("$LPI" '>redirect.tex' 2> /dev/null)" = "contents" ]; then
  pass "read a file name that starts with '>'"
else
  fail "did not read a file name that starts with '>'"
fi
# A 2-argument `open` strips the `>` and opens `redirect.tex` for writing.
if [ -e redirect.tex ]; then
  fail "opened a file name that starts with '>' for writing"
else
  pass "did not open a file name that starts with '>' for writing"
fi

### An ordinary document is still processed:  `\input` is inlined and comments
### are stripped.

mkdir "$work/ordinary"
cat > "$work/ordinary/main.tex" << 'TEX'
\documentclass{article}
\begin{document}
\input{section}
% a comment
\end{document}
TEX
cat > "$work/ordinary/section.tex" << 'TEX'
Section text.
TEX
cd "$work/ordinary"
# The blank line after the inlined text is the newline that terminated the
# `\input{section}` line; the inlined file supplies its own.
expected_inline='\documentclass{article}
\begin{document}
Section text.

%
\end{document}'
if [ "$("$LPI" main.tex)" = "$expected_inline" ]; then
  pass "inlined an ordinary document"
else
  fail "did not inline an ordinary document"
  "$LPI" main.tex
fi
expected_list='main.tex
section.tex'
if [ "$("$LPI" --list main.tex)" = "$expected_list" ]; then
  pass "listed the inputs of an ordinary document"
else
  fail "did not list the inputs of an ordinary document"
  "$LPI" --list main.tex
fi

exit $status
