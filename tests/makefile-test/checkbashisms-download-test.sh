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
# content, so this test makes no network connection.  The checksum program is
# replaced by a stub that logs the checksum line the `Makefile` pipes into it
# and then defers to the real program.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
MAKEFILE="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/Makefile"
MAKE="${MAKE:-make}"

# Mirror the `Makefile`'s choice of checksum program, so that the stub below
# shadows the program that the `Makefile` will invoke.
if command -v sha256sum > /dev/null 2>&1; then
  SHA256_NAME=sha256sum
  REAL_SHA256="$(command -v sha256sum)"
  sha256() { "$REAL_SHA256" | cut -d' ' -f1; }
elif command -v shasum > /dev/null 2>&1; then
  SHA256_NAME=shasum
  REAL_SHA256="$(command -v shasum)"
  sha256() { "$REAL_SHA256" -a 256 | cut -d' ' -f1; }
else
  echo "SKIP: neither sha256sum nor shasum is installed"
  exit 0
fi
export REAL_SHA256

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

# A checksum program that logs the checksum line piped into it, then defers to
# the real program, so that this test can see what the `Makefile` verified
# against.
cat > "$work/bin/$SHA256_NAME" << 'END'
#!/bin/sh
input="$(cat)"
printf '%s\n' "$input" >> "$SHA256_LOG"
printf '%s\n' "$input" | "$REAL_SHA256" "$@"
END
chmod +x "$work/bin/$SHA256_NAME"

WGET_LOG="$work/wget.log"
WGET_FAILS="$work/wget-fails"
WGET_PAYLOAD="$work/payload"
SHA256_LOG="$work/sha256.log"
export WGET_LOG WGET_FAILS WGET_PAYLOAD SHA256_LOG
PATH="$work/bin:$PATH"
export PATH

printf '#!/usr/bin/perl\nprint "fake checkbashisms\\n";\n' > "$WGET_PAYLOAD"
payload_sha="$(sha256 < "$WGET_PAYLOAD")"

# Runs `make` with the checksum of the canned payload, so that the download
# succeeds.  The `Makefile`'s own pinned checksum is exercised separately,
# below.
run_make() {
  : > "$WGET_LOG"
  : > "$SHA256_LOG"
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

### The `Makefile`'s own pinned checksum is what the rule verifies against.
###
### Every other `make` invocation in this test overrides CHECKBASHISMS_SHA256,
### so without these checks the pinned constant could be deleted or corrupted
### -- breaking every real user -- with the test suite staying green.

pinned_sha="$(sed -n 's/^CHECKBASHISMS_SHA256[[:space:]]*=[[:space:]]*//p' "$MAKEFILE" | tr -d '[:space:]')"
case "$pinned_sha" in
  *[!0-9a-f]*) pinned_is_hex=no ;;
  *) pinned_is_hex=yes ;;
esac
if [ "$pinned_is_hex" = yes ] && [ "${#pinned_sha}" -eq 64 ]; then
  pass "CHECKBASHISMS_SHA256 is 64 hexadecimal digits"
else
  fail "CHECKBASHISMS_SHA256 is not 64 hexadecimal digits: \`$pinned_sha\`"
fi

: > "$WGET_LOG"
: > "$SHA256_LOG"
if (cd "$work" && "$MAKE" checkbashisms) > "$work/make.log" 2>&1; then
  fail "zero exit status when the download does not match the pinned checksum"
else
  pass "nonzero exit status when the download does not match the pinned checksum"
fi
used_sha="$(cut -d' ' -f1 < "$SHA256_LOG")"
if [ "$used_sha" = "$pinned_sha" ]; then
  pass "the rule verified against the pinned CHECKBASHISMS_SHA256"
else
  fail "the rule verified against \`$used_sha\` rather than the pinned \`$pinned_sha\`"
fi
rm -f "$work/checkbashisms" "$work/checkbashisms.tmp"

### With no checksum program, the rule diagnoses that rather than downloading
### an unverifiable file or blaming the checksum.

: > "$WGET_LOG"
if (cd "$work" && "$MAKE" checkbashisms SHA256_CHECK= \
  CHECKBASHISMS_SHA256="$payload_sha") > "$work/make.log" 2>&1; then
  fail "zero exit status when no checksum program is available"
else
  pass "nonzero exit status when no checksum program is available"
fi
if grep -q "neither sha256sum nor shasum" "$work/make.log"; then
  pass "a missing checksum program is diagnosed as such"
else
  fail "a missing checksum program is not diagnosed as such"
  cat "$work/make.log"
fi
if [ "$(wget_calls)" = 0 ]; then
  pass "no download is attempted without a checksum program"
else
  fail "a download was attempted without a checksum program"
fi
if [ -e "$work/checkbashisms" ] || [ -e "$work/checkbashisms.tmp" ]; then
  fail "a missing checksum program left a file behind"
  rm -f "$work/checkbashisms" "$work/checkbashisms.tmp"
else
  pass "a missing checksum program left no file behind"
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
