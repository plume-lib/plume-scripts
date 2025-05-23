all: style-check test

style-fix: python-style-fix shell-style-fix
style-check: python-style-check python-typecheck shell-style-check

test:
	${MAKE} -C tests test

PYTHON_FILES=$(wildcard *.py) $(shell grep -r -l --exclude='*.py' --exclude='*~' --exclude='*.tar' --exclude=gradlew --exclude-dir=.git '^\#! \?\(/bin/\|/usr/bin/env \)python')
install-mypy:
	@if ! command -v mypy ; then pip install mypy ; fi
install-ruff:
	@if ! command -v ruff ; then pipx install ruff ; fi
python-style-fix: install-ruff
	@ruff format ${PYTHON_FILES}
	@ruff -q check ${PYTHON_FILES} --fix
python-style-check: install-ruff
	@ruff -q format --check ${PYTHON_FILES}
	@ruff -q check ${PYTHON_FILES}
python-typecheck: install-mypy
	@mypy --strict ${PYTHON_FILES} > /dev/null 2>&1 || true
	@mypy --install-types --non-interactive
	mypy --strict --ignore-missing-imports ${PYTHON_FILES}

SH_SCRIPTS   = $(shell grep -r -l --exclude='*~' --exclude='*.tar' --exclude=gradlew --exclude-dir=.git '^\#! \?\(/bin/\|/usr/bin/env \)sh'   | grep -v addrfilter | grep -v cronic-orig | grep -v mail-stackoverflow.sh)
BASH_SCRIPTS = $(shell grep -r -l --exclude='*~' --exclude='*.tar' --exclude=gradlew --exclude-dir=.git '^\#! \?\(/bin/\|/usr/bin/env \)bash' | grep -v addrfilter | grep -v cronic-orig | grep -v mail-stackoverflow.sh)

shell-style-fix:
	shfmt -w -i 2 -ci -bn -sr ${SH_SCRIPTS} ${BASH_SCRIPTS}
	shellcheck -x -P SCRIPTDIR --format=diff ${SH_SCRIPTS} ${BASH_SCRIPTS} | patch -p1
shell-style-check:
	shfmt -d -i 2 -ci -bn -sr ${SH_SCRIPTS} ${BASH_SCRIPTS}
	shellcheck -x -P SCRIPTDIR --format=gcc ${SH_SCRIPTS} ${BASH_SCRIPTS}
	checkbashisms -l ${SH_SCRIPTS}

showvars:
	@echo "PYTHON_FILES=${PYTHON_FILES}"
	@echo "SH_SCRIPTS=${SH_SCRIPTS}"
	@echo "BASH_SCRIPTS=${BASH_SCRIPTS}"

