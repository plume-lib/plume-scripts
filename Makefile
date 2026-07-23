.PHONY: all test clean

all: checkbashisms

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
