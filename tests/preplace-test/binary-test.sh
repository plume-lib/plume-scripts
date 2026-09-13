#!/bin/sh

# Tests that `preplace` does not rewrite binary files.
#
# `preplace` used to skip only files named "*.class" or "*.pyc".  Any other
# binary file under the current directory -- a .jar, .png, or .o, say -- whose
# bytes happened to match the regex was rewritten and thereby corrupted.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
PREPLACE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/preplace"

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

# make_binary FILE: writes a file that contains the text "OLD" but is binary,
# because it also contains NUL and other non-text bytes.
make_binary() {
  printf 'OLD\000\001\002\003\004\005\006\007\010\016\017\177\200\201\202\203OLD\n' > "$1"
}

### A binary file is left alone, whatever its extension.

for ext in class pyc jar png o ""; do
  if [ -z "$ext" ]; then
    file="$work/noextension"
  else
    file="$work/binary.$ext"
  fi
  make_binary "$file"
  before="$(cksum < "$file")"
  (cd "$work" && "$PREPLACE" OLD NEW)
  if [ "$(cksum < "$file")" = "$before" ]; then
    pass "did not rewrite $(basename -- "$file")"
  else
    fail "rewrote $(basename -- "$file")"
  fi
  rm -f "$file"
done

### A text file is still rewritten.

printf 'an OLD line\nanother OLD line\n' > "$work/text.txt"
# A UTF-8 file is text, not binary, even though it contains non-ASCII bytes.
printf 'caf\303\251 OLD na\303\257ve r\303\251sum\303\251\n' > "$work/utf8.txt"
(cd "$work" && "$PREPLACE" OLD NEW)
if [ "$(cat "$work/text.txt")" = "$(printf 'an NEW line\nanother NEW line')" ]; then
  pass "rewrote a text file"
else
  fail "did not rewrite a text file"
  cat "$work/text.txt"
fi
if [ "$(cat "$work/utf8.txt")" = "$(printf 'caf\303\251 NEW na\303\257ve r\303\251sum\303\251')" ]; then
  pass "rewrote a UTF-8 text file"
else
  fail "did not rewrite a UTF-8 text file"
  cat "$work/utf8.txt"
fi

exit "$status"
