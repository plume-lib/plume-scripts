# -*- makefile -*-

# This Makefile fragment defines targets:
# * style-fix
# * style-check
# * plume-scripts-update
#
# To use it, add to another Makefile:
# (Add this after the default target is defined.)
# (The variable definitions are optional.)
#
# # Code style; defines `style-check` and `style-fix`.
# SH_SCRIPTS_USER := dots/.aliases dots/.environment dots/.profile
# BASH_SCRIPTS_USER := dots/.bashrc dots/.bash_profile
# CODE_STYLE_EXCLUSIONS_USER := --exclude-dir apheleia --exclude-dir 'apheleia-*' --exclude-dir=mew --exclude=csail-athena-tickets.bash --exclude=conda-initialize.sh --exclude=addrfilter
# ifeq (,$(wildcard .plume-scripts))
# dummy != git clone -q https://github.com/plume-lib/plume-scripts.git .plume-scripts
# endif
# include .plume-scripts/code-style.mak

# `checkbashisms` is not included by source because it uses the GPL.
ifeq (,$(wildcard .plume-scripts/checkbashisms))
dummy2 != (cd .plume-scripts \
   && wget -q -N https://homes.cs.washington.edu/~mernst/software/checkbashisms \
   && chmod +x checkbashisms)
endif
# `checkbashisms` is not included to avoid code duplication.
ifeq (,$(wildcard .ruff.toml))
dummy3 != ln -s .plume-scripts/.ruff.toml .ruff.toml
endif
ifeq (,$(wildcard .pymarkdown))
dummy4 != ln -s .plume-scripts/.pymarkdown .pymarkdown
endif

CODE_STYLE_EXCLUSIONS := --exclude-dir=.git --exclude-dir=.venv --exclude-dir=.plume-scripts --exclude-dir=build --exclude='\#*' --exclude='*~' --exclude='*.bak' --exclude='*.tar' --exclude='*.tdy' --exclude=gradlew

.PHONY: style-fix style-check


## HTML
.PHONY: html-style-fix html-style-check
style-fix: html-style-fix
style-check: html-style-check
# Any file ending with ".html".
HTML_FILES   := $(shell grep -r -l --include='*.html' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .)
html-style-fix:
ifneq ($(strip ${HTML_FILES}),)
	:
endif
html-style-check:
ifneq ($(strip ${HTML_FILES}),)
# The first run of `uv run html5validator` may output "Downloading html5validator ..." to standard error.
	@uv run html5validator --version > /dev/null 2>&1 || uv run html5validator --version
	@.plume-scripts/cronic uv run html5validator ${HTML_FILES}
endif
showvars::
	@echo "HTML_FILES=${HTML_FILES}"


## Markdown
.PHONY: markdown-style-fix markdown-style-check
style-fix: markdown-style-fix
style-check: markdown-style-check
MARKDOWN_FILES   := $(shell grep -r -l --include='*.md' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .)
ifneq ($(strip ${MARKDOWN_FILES}),)
# Markdown linters are listed in order of increasing precedence.
PYMARKDOWNLNT_EXISTS := $(shell if uv run pymarkdownlnt version > /dev/null 2>&1; then echo "yes"; fi)
ifdef PYMARKDOWNLNT_EXISTS
MARKDOWN_STYLE_FIX := uv run pymarkdownlnt fix
MARKDOWN_STYLE_CHECK := uv run pymarkdownlnt scan
endif
MARKDOWNLINT_CLI2 := $(shell command -v markdownlint-cli2 2> /dev/null)
ifdef MARKDOWNLINT_CLI2
MARKDOWN_STYLE_FIX := markdownlint-cli2 --fix "\#node_modules"
MARKDOWN_STYLE_CHECK := markdownlint-cli2 "\#node_modules"
endif
endif # ifneq ($(strip ${MARKDOWN_FILES}),)
markdown-style-fix:
ifneq ($(strip ${MARKDOWN_FILES}),)
ifndef MARKDOWN_STYLE_FIX
	echo Cannot find 'uv run pymarkdownlnt' or 'markdownlint-cli2'
	-uv run pymarkdownlnt version
	-command -v markdownlint-cli2
	false
endif
	.plume-scripts/cronic ${MARKDOWN_STYLE_FIX} ${MARKDOWN_FILES}
endif
markdown-style-check:
ifneq ($(strip ${MARKDOWN_FILES}),)
ifndef MARKDOWN_STYLE_CHECK
	echo Cannot find 'uv run pymarkdownlnt' or 'markdownlint-cli2'
	-uv run pymarkdownlnt version
	-command -v markdownlint-cli2
	false
endif
	.plume-scripts/cronic ${MARKDOWN_STYLE_CHECK} ${MARKDOWN_FILES}
endif
showvars::
	@echo "MARKDOWN_FILES=${MARKDOWN_FILES}"
	@echo "PYMARKDOWNLNT_EXISTS=${PYMARKDOWNLNT_EXISTS}"
	@echo "MARKDOWN_STYLE_FIX=${MARKDOWN_STYLE_FIX}"
	@echo "MARKDOWN_STYLE_CHECK=${MARKDOWN_STYLE_CHECK}"
	@echo "MARKDOWNLINT_CLI2=${MARKDOWNLINT_CLI2}"


## Perl
.PHONY: perl-style-fix perl-style-check
style-fix: perl-style-fix
style-check: perl-style-check
# Any file ending with ".pl" or ".pm" or containing a Perl shebang line.
PERL_FILES   := $(shell grep -r -l --include='*.pl' --include='*.pm' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .) $(shell grep -r -l --exclude='*.pl' --exclude='*.pm' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/\|/usr/bin/env \)perl' .)
perl-style-fix:
ifneq ($(strip ${PERL_FILES}),)
# I don't think that perltidy is an improvement.
#	@perltidy -w -b -bext='/' -gnu ${PERL_FILES}
#	@find . -name '*.tdy' -type f -delete
endif
perl-style-check:
ifneq ($(strip ${PERL_FILES}),)
# I don't think that perltidy is an improvement.
#	@perltidy -w ${PERL_FILES}
#	@find . -name '*.tdy' -type f -delete
endif
showvars::
	@echo "PERL_FILES=${PERL_FILES}"


## Python
.PHONY: python-style-fix python-style-check python-typecheck
style-fix: python-style-fix
style-check: python-style-check python-typecheck
# Any file ending with ".py" or containing a Python shebang line.
PYTHON_FILES:=$(shell grep -r -l --include='*.py' ${CODE_STYLE_EXCLUSIONS}  ${CODE_STYLE_EXCLUSIONS_USER} '^' .) $(shell grep -r -l --exclude='*.py' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/\|/usr/bin/env \)python' .)
python-style-fix:
ifneq ($(strip ${PYTHON_FILES}),)
# The first run of `uvx ruff` may output "Downloading ruff ..." to standard error.
	@uvx ruff --version > /dev/null 2>&1 || uvx ruff --version
	@.plume-scripts/cronic uvx ruff format ${PYTHON_FILES}
	@.plume-scripts/cronic uvx ruff check ${PYTHON_FILES} --fix
endif
python-style-check:
ifneq ($(strip ${PYTHON_FILES}),)
# The first run of `uvx ruff` may output "Downloading ruff ..." to standard error.
	@uvx ruff --version > /dev/null 2>&1 || uvx ruff --version
	@.plume-scripts/cronic uvx ruff format --check ${PYTHON_FILES}
	@.plume-scripts/cronic uvx ruff check ${PYTHON_FILES}
endif
python-typecheck:
ifneq ($(strip ${PYTHON_FILES}),)
# The first run of `uv run ty check` may output "Using CPython ..." to standard error.
	@uv run ty check -h > /dev/null 2>&1 || uv run ty check -h
# Problem: `ty` ignores files passed on the command line that do not end with `.py`.
	@.plume-scripts/cronic uv run ty check --error-on-warning --no-progress ${PYTHON_FILES}
endif
showvars::
	@echo "PYTHON_FILES=${PYTHON_FILES}"


## Shell
.PHONY: shell-style-fix shell-style-check
style-fix: shell-style-fix
style-check: shell-style-check
# Files ending with ".sh" might be bash or Posix sh, so don't make any assumption about them.
SH_SCRIPTS   := ${SH_SCRIPTS_USER} $(shell grep -r -l ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/env \)sh' .)
# Any file ending with ".bash" or containing a bash shebang line.
BASH_SCRIPTS := ${BASH_SCRIPTS_USER} $(shell grep -r -l --include='*.bash' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .) $(shell grep -r -l --exclude='*.bash' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/env \)bash' .)
SH_AND_BASH_SCRIPTS := ${SH_SCRIPTS} ${BASH_SCRIPTS}
shell-style-fix:
ifneq ($(strip ${SH_AND_BASH_SCRIPTS}),)
	@.plume-scripts/cronic shfmt -w -i 2 -ci -bn -sr ${SH_AND_BASH_SCRIPTS}
	@shellcheck -x -P SCRIPTDIR --format=diff ${SH_AND_BASH_SCRIPTS} | patch -p1
endif
shell-style-check:
ifneq ($(strip ${SH_AND_BASH_SCRIPTS}),)
	@.plume-scripts/cronic shfmt -d -i 2 -ci -bn -sr ${SH_AND_BASH_SCRIPTS}
	@.plume-scripts/cronic shellcheck -x -P SCRIPTDIR --format=gcc ${SH_AND_BASH_SCRIPTS}
endif
ifneq ($(strip ${SH_SCRIPTS}),)
	@.plume-scripts/cronic .plume-scripts/checkbashisms -l ${SH_SCRIPTS}
endif
showvars::
	@echo "SH_SCRIPTS=${SH_SCRIPTS}"
	@echo "BASH_SCRIPTS=${BASH_SCRIPTS}"


plume-scripts-update:
	@.plume-scripts/cronic git -q -C .plume-scripts pull --ff-only
