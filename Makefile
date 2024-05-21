all: check-python-style shell-script-style test

test:
	${MAKE} -C tests test

PYTHON_FILES=$(wildcard *.py)

python-style:
	ruff format ${PYTHON_FILES}
	ruff check ${PYTHON_FILES} --fix

check-python-style:
	ruff format ${PYTHON_FILES}
	ruff check ${PYTHON_FILES} --fix

SH_SCRIPTS = $(shell grep -r -l '^\#!/bin/sh' * | grep -v .git | grep -v "~" | grep -v cronic-orig)
BASH_SCRIPTS = $(shell grep -r -l '^\#!/bin/bash' * | grep -v .git | grep -v "~" | grep -v cronic-orig)

shell-script-style:
	shellcheck --format=gcc ${SH_SCRIPTS} ${BASH_SCRIPTS}
	checkbashisms ${SH_SCRIPTS}

showvars:
	@echo "PYTHON_FILES=${PYTHON_FILES}"
	@echo "SH_SCRIPTS=${SH_SCRIPTS}"
	@echo "BASH_SCRIPTS=${BASH_SCRIPTS}"

