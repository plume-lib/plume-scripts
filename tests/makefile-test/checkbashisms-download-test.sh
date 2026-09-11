#!/bin/sh

# Tests how the top-level `Makefile` downloads `checkbashisms`.
#
# The download must happen only when `checkbashisms` is both absent and asked
# for -- not during every `make` invocation, as a `$(shell wget ...)` variable
# assignment would do.  The downloaded file must be verified against a checksum
# and made executable, and a failed download or a checksum mismatch must leave
# no `checkbashisms` behind.
#
# `wget` is replaced by a stub that logs its invocations and writes canned
# content, so this test makes no network connection.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
MAKEFILE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/Makefile"
MAKE="${MAKE:-make}"

if command -v sha256sum > /dev/null 2>&1; then
  sha256() { sha256sum | cut -d' ' -f1; }
elif command -v shasum > /dev/null 2>&1; then
  sha256() { shasum -a 256 | cut -d' ' -f1; }
else
  echo "SKIP: neither sha256sum nor shasum is installed"
  exit 0
fi

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

### Set up a copy of the repository that contains only what this test needs.

cp "$MAKEFILE" "$work/Makefile"
mkdir "$work/tests" "$work/bin"
cat > "$work/tests/Makefile" << 'END'
.PHONY: test clean
test:
	@echo "stub tests"
clean:
	@echo "stub clean"
END

# A `wget` that logs its invocation and writes `$work/payload` to the file
# named by `-O`, or, like real wget, to the URL's last component when there is
# no `-O`.  If `$work/wget-fails` exists, it fails instead.
cat > "$work/bin/wget" << 'END'
#!/bin/sh
echo "wget $*" >> "$WGET_LOG"
if [ -e "$WGET_FAILS" ]; then
  exit 8
fi
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -O) out="$2"; shift ;;
    -*) ;;
    *) url="$1" ;;
  esac
  shift
done
# Like real wget, write to the URL's last component when there is no `-O`.
if [ -z "$out" ]; then
  out="${url##*/}"
fi
cat "$WGET_PAYLOAD" > "$out"
END
chmod +x "$work/bin/wget"

WGET_LOG="$work/wget.log"
WGET_FAILS="$work/wget-fails"
WGET_PAYLOAD="$work/payload"
export WGET_LOG WGET_FAILS WGET_PAYLOAD
PATH="$work/bin:$PATH"
export PATH

printf '#!/usr/bin/perl\nprint "fake checkbashisms\\n";\n' > "$WGET_PAYLOAD"
payload_sha="$(sha256 < "$WGET_PAYLOAD")"

run_make() {
  : > "$WGET_LOG"
  (cd "$work" && "$MAKE" "$@" CHECKBASHISMS_SHA256="$payload_sha") \
    > "$work/make.log" 2>&1
}

wget_calls() {
  wc -l < "$WGET_LOG" | tr -d ' '
}

### `make clean` does not download anything.

if run_make clean; then
  pass "zero exit status for \`make clean\`"
else
  fail "nonzero exit status for \`make clean\`"
  cat "$work/make.log"
fi
if [ "$(wget_calls)" = 0 ]; then
  pass "\`make clean\` did not run wget"
else
  fail "\`make clean\` ran wget $(wget_calls) time(s)"
fi
if [ -e "$work/checkbashisms" ]; then
  fail "\`make clean\` created checkbashisms"
  rm -f "$work/checkbashisms"
else
  pass "\`make clean\` did not create checkbashisms"
fi

### `make test` does not download anything.

if run_make test; then
  pass "zero exit status for \`make test\`"
else
  fail "nonzero exit status for \`make test\`"
  cat "$work/make.log"
fi
if [ "$(wget_calls)" = 0 ]; then
  pass "\`make test\` did not run wget"
else
  fail "\`make test\` ran wget $(wget_calls) time(s)"
fi
if [ -e "$work/checkbashisms" ]; then
  fail "\`make test\` created checkbashisms"
  rm -f "$work/checkbashisms"
else
  pass "\`make test\` did not create checkbashisms"
fi

### A failed download leaves no `checkbashisms` and no temporary file.

: > "$WGET_FAILS"
if run_make checkbashisms; then
  fail "zero exit status when the download fails"
else
  pass "nonzero exit status when the download fails"
fi
if [ -e "$work/checkbashisms" ] || [ -e "$work/checkbashisms.tmp" ]; then
  fail "a failed download left a file behind"
  rm -f "$work/checkbashisms" "$work/checkbashisms.tmp"
else
  pass "a failed download left no file behind"
fi
rm -f "$WGET_FAILS"

### A checksum mismatch leaves no `checkbashisms` and no temporary file.

: > "$WGET_LOG"
if (cd "$work" && "$MAKE" checkbashisms CHECKBASHISMS_SHA256=0123456789abcdef) \
  > "$work/make.log" 2>&1; then
  fail "zero exit status for a checksum mismatch"
else
  pass "nonzero exit status for a checksum mismatch"
fi
if [ -e "$work/checkbashisms" ] || [ -e "$work/checkbashisms.tmp" ]; then
  fail "a checksum mismatch left a file behind"
  rm -f "$work/checkbashisms" "$work/checkbashisms.tmp"
else
  pass "a checksum mismatch left no file behind"
fi

### A successful `make` downloads the file once and makes it executable.

if run_make; then
  pass "zero exit status for \`make\`"
else
  fail "nonzero exit status for \`make\`"
  cat "$work/make.log"
fi
if [ "$(wget_calls)" = 1 ]; then
  pass "\`make\` ran wget once"
else
  fail "\`make\` ran wget $(wget_calls) time(s)"
fi
if [ -x "$work/checkbashisms" ]; then
  pass "downloaded checkbashisms is executable"
else
  fail "downloaded checkbashisms is not executable"
  ls -l "$work/checkbashisms" || true
fi
if [ "$(sha256 < "$work/checkbashisms")" = "$payload_sha" ]; then
  pass "downloaded checkbashisms has the expected contents"
else
  fail "downloaded checkbashisms has unexpected contents"
fi
if [ -e "$work/checkbashisms.tmp" ]; then
  fail "a successful download left a temporary file behind"
else
  pass "a successful download left no temporary file behind"
fi

### A second `make` does not download again.

if run_make; then
  pass "zero exit status for a second \`make\`"
else
  fail "nonzero exit status for a second \`make\`"
  cat "$work/make.log"
fi
if [ "$(wget_calls)" = 0 ]; then
  pass "a second \`make\` did not run wget"
else
  fail "a second \`make\` ran wget $(wget_calls) time(s)"
fi

exit "$status"
