all: style-check test

# `checkbashisms` is not included by source because it uses the GPL.
ifeq (,$(wildcard .plume-scripts/checkbashisms))
  (cd .plume-scripts \
   && wget -q -N https://homes.cs.washington.edu/~mernst/software/checkbashisms \
   && chmod +x checkbashisms)
endif

test:
	${MAKE} -C tests test

clean:
	make -C tests clean

# Code style; defines `style-check` and `style-fix`.
ifeq (,$(wildcard .plume-scripts))
  git clone https://github.com/plume-lib/plume-scripts.git .plume-scripts
endif
include .plume-scripts/code-style.mak
