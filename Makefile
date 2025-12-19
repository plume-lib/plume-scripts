.PHONY: all test clean

all: style-check test

# Code style; defines `style-check` and `style-fix`.
CODE_STYLE_EXCLUSIONS_USER:= --exclude=cronic-orig --exclude=checkbashisms
ifeq (,$(wildcard .plume-scripts))
dummy := $(ln -s . .plume-scripts)
endif
include .plume-scripts/code-style.mak

# `checkbashisms` is not included by source because it is licensed under the GPL.
ifeq (,$(wildcard checkbashisms))
dummy2 := $(shell wget -q -N https://homes.cs.washington.edu/~mernst/software/checkbashisms)
endif

test:
	${MAKE} -C tests test

clean:
	make -C tests clean
