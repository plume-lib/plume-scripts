.PHONY: all test clean

all: style-check test

# Code style; defines `style-check` and `style-fix`.
CODE_STYLE_EXCLUSIONS_USER:= --exclude=cronic-orig --exclude=checkbashisms
PLUME_SCRIPTS ?= .
include ${PLUME_SCRIPTS}/code-style.mak

# `checkbashisms` is not included by source because it is licensed under the GPL.
ifeq (,$(wildcard checkbashisms))
dummy := $(shell wget -q https://homes.cs.washington.edu/~mernst/software/checkbashisms)
endif

checkbashisms:
	wget -q https://homes.cs.washington.edu/~mernst/software/checkbashisms
	chmod +x $@

test:
	${MAKE} -C tests test

clean:
	make -C tests clean
