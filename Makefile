all: style-check test

style-fix: python-style-fix shell-style-fix
style-check: python-style-check python-typecheck shell-style-check

test:
	${MAKE} -C tests test

clean:
	make -C tests clean

style-fix: python-style-fix
style-check: python-style-check python-typecheck
PYTHON_FILES:=$(wildcard **/*.py) $(shell grep -r -l --exclude-dir=.git --exclude-dir=.venv --exclude='*.py' --exclude='#*' --exclude='*~' --exclude='*.tar' --exclude=gradlew --exclude=lcb_runner '^\#! \?\(/bin/\|/usr/bin/\|/usr/bin/env \)python')
python-style-fix:
ifneq (${PYTHON_FILES},)
#	@uvx ruff --version
	@uvx ruff -q format ${PYTHON_FILES}
	@uvx ruff -q check ${PYTHON_FILES} --fix
endif
python-style-check:
ifneq (${PYTHON_FILES},)
#	@uvx ruff --version
	@uvx ruff -q format --check ${PYTHON_FILES}
	@uvx ruff -q check ${PYTHON_FILES}
endif
python-typecheck:
ifneq (${PYTHON_FILES},)
	@uv run ty check --error-on-warning --no-progress
endif
showvars::
	@echo "PYTHON_FILES=${PYTHON_FILES}"

style-fix: shell-style-fix
style-check: shell-style-check
SH_SCRIPTS   := $(shell grep -r -l --exclude-dir=.git --exclude-dir=.plume-scripts --exclude='#*' --exclude='*~' --exclude='*.tar' --exclude=gradlew '^\#! \?\(/bin/\|/usr/bin/env \)sh'   | grep -v addrfilter | grep -v cronic-orig | grep -v mail-stackoverflow.sh)
BASH_SCRIPTS := $(shell grep -r -l --exclude-dir=.git --exclude-dir=.plume-scripts --exclude='#*' --exclude='*~' --exclude='*.tar' --exclude=gradlew '^\#! \?\(/bin/\|/usr/bin/env \)bash' | grep -v addrfilter | grep -v cronic-orig | grep -v mail-stackoverflow.sh)
CHECKBASHISMS := $(shell if command -v checkbashisms > /dev/null ; then \
   echo "checkbashisms" ; \
 else \
   wget -q -N https://homes.cs.washington.edu/~mernst/software/checkbashisms && \
   mv checkbashisms .checkbashisms && \
   chmod +x ./.checkbashisms && \
   echo "./.checkbashisms" ; \
 fi)
shell-style-fix:
ifneq ($(SH_SCRIPTS)$(BASH_SCRIPTS),)
	@shfmt -w -i 2 -ci -bn -sr ${SH_SCRIPTS} ${BASH_SCRIPTS}
	@shellcheck -x -P SCRIPTDIR --format=diff ${SH_SCRIPTS} ${BASH_SCRIPTS} | patch -p1
endif
shell-style-check:
ifneq ($(SH_SCRIPTS)$(BASH_SCRIPTS),)
	@shfmt -d -i 2 -ci -bn -sr ${SH_SCRIPTS} ${BASH_SCRIPTS}
	@shellcheck -x -P SCRIPTDIR --format=gcc ${SH_SCRIPTS} ${BASH_SCRIPTS}
endif
ifneq ($(SH_SCRIPTS),)
	@${CHECKBASHISMS} -l ${SH_SCRIPTS}
endif
showvars::
	@echo "SH_SCRIPTS=${SH_SCRIPTS}"
	@echo "BASH_SCRIPTS=${BASH_SCRIPTS}"
	@echo "CHECKBASHISMS=${CHECKBASHISMS}"
