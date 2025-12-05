all: style-check test

# Code style; defines `style-check` and `style-fix`.
ifeq (,$(wildcard .plume-scripts))
# TODO: Remove --branch
dummy != $(shell git clone -q --branch code-style-mak https://github.com/plume-lib/plume-scripts.git .plume-scripts)
endif
include .plume-scripts/code-style.mak

# `checkbashisms` is not included by source because it is licensed under the GPL.
ifeq (,$(wildcard checkbashisms))
dummy2 != wget -q -N https://homes.cs.washington.edu/~mernst/software/checkbashisms
endif

test:
	${MAKE} -C tests test

clean:
	make -C tests clean
