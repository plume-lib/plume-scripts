.PHONY: all test clean

all: checkbashisms

# `checkbashisms` is not included by source because it is licensed under the GPL.
# It is downloaded by the rule below, which runs only when `checkbashisms` is
# absent *and* something asks for it.  (Downloading in a `$(shell ...)`
# assignment would instead download during every `make` invocation, including
# `make clean`.)
CHECKBASHISMS_URL = https://homes.cs.washington.edu/~mernst/software/checkbashisms
# Update this whenever the file at CHECKBASHISMS_URL is updated.
CHECKBASHISMS_SHA256 = 2113bd9feba1f9d8e5a0fed886f907420b7a6b533234aaf5653b2ca317e49eac
# `sha256sum` exists on GNU/Linux, `shasum` on macOS.
SHA256_CHECK = $(shell if command -v sha256sum > /dev/null 2>&1; then echo sha256sum; else echo shasum -a 256; fi) --check --status

# Downloads to a temporary file and renames it into place, so that a failed
# download or a failed checksum leaves no `checkbashisms` at all, rather than a
# truncated, unverified, or non-executable one.
checkbashisms:
	wget -q -O $@.tmp ${CHECKBASHISMS_URL} || { rm -f $@.tmp; false; }
	echo "${CHECKBASHISMS_SHA256}  $@.tmp" | ${SHA256_CHECK} || { echo "$@: checksum mismatch in download from ${CHECKBASHISMS_URL}" >&2; rm -f $@.tmp; false; }
	chmod +x $@.tmp
	mv -f $@.tmp $@

test:
	${MAKE} -C tests test

clean:
	${MAKE} -C tests clean
