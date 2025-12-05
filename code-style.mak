# -*- makefile -*-

# This Makefile fragment defines targets:
# * style-fix
# * style-check
# * plume-scripts-update
#
# To use it, add to another Makefile (after the default target is defined):
#
# ifeq (,$(wildcard .plume-scripts))
# dummy != $(shell git clone -q https://github.com/plume-lib/plume-scripts.git .plume-scripts)
# endif
# include .plume-scripts/code-style.mak
#
# You can also define variables such as:
#
# SH_SCRIPTS_USER := dots/.aliases dots/.environment dots/.profile
# BASH_SCRIPTS_USER := dots/.bashrc dots/.bash_profile
# CODE_STYLE_EXCLUSIONS_USER := --exclude-dir apheleia --exclude-dir 'apheleia-*' --exclude-dir=mew

# `checkbashisms` is not included by source because it uses the GPL.
ifeq (,$(wildcard .plume-scripts/checkbashisms))
dummy2 != (cd .plume-scripts \
   && wget -q -N https://homes.cs.washington.edu/~mernst/software/checkbashisms \
   && chmod +x checkbashisms)
endif

CODE_STYLE_EXCLUSIONS := --exclude-dir=.git --exclude-dir=.venv --exclude-dir=.plume-scripts --exclude='\#*' --exclude='*~' --exclude='*.bak' --exclude='*.tar' --exclude='*.tdy' --exclude=gradlew

style-fix: perl-style-fix
style-check: perl-style-check
# Any file ending with ".pl" or ".pm" or containing a Python shebang line.
PERL_FILES   := $(shell grep -r -l --include='*.pl' --include='*.pm' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^') $(shell grep -r -l --exclude='*.pl' --exclude='*.pm' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/\|/usr/bin/env \)perl')
perl-style-fix:
ifneq (${PERL_FILES},)
	@rm -rf *.tdy
	@perltidy -bext='/' -gnu ${PERL_FILES}
endif
perl-style-check:
ifneq (${PERL_FILES},)
	@rm -rf *.tdy
	@perltidy -w ${PERL_FILES}
endif
showvars::
	@echo "PERL_FILES=${PERL_FILES}"

style-fix: python-style-fix
style-check: python-style-check python-typecheck
# Any file ending with ".py" or containing a Python shebang line.
PYTHON_FILES:=$(shell grep -r -l --include='*.py' ${CODE_STYLE_EXCLUSIONS}  ${CODE_STYLE_EXCLUSIONS_USER} '^') $(shell grep -r -l --exclude='*.py' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/\|/usr/bin/env \)python')
python-style-fix:
ifneq (${PYTHON_FILES},)
#	@uvx ruff --version
	@.plume-scripts/cronic uvx ruff format ${PYTHON_FILES}
	@.plume-scripts/cronic uvx ruff check ${PYTHON_FILES} --fix
endif
python-style-check:
ifneq (${PYTHON_FILES},)
#	@uvx ruff --version
	@.plume-scripts/cronic uvx ruff format --check ${PYTHON_FILES}
	@.plume-scripts/cronic uvx ruff check ${PYTHON_FILES}
endif
python-typecheck:
ifneq (${PYTHON_FILES},)
	@.plume-scripts/cronic uv run ty check --error-on-warning --no-progress
endif
showvars::
	@echo "PYTHON_FILES=${PYTHON_FILES}"

style-fix: shell-style-fix
style-check: shell-style-check
# Files ending with ".sh" might be bash or Posix sh, so don't make any assumption about them.
SH_SCRIPTS   := ${SH_SCRIPTS_USER} $(shell grep -r -l ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/env \)sh')
# Any file ending with ".bash" or containing a Python shebang line.
BASH_SCRIPTS := ${BASH_SCRIPTS_USER} $(shell grep -r -l --include='*.bash' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^') $(shell grep -r -l --exclude='*.bash' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/env \)bash')
shell-style-fix:
ifneq ($(SH_SCRIPTS)$(BASH_SCRIPTS),)
	@.plume-scripts/cronic shfmt -w -i 2 -ci -bn -sr ${SH_SCRIPTS} ${BASH_SCRIPTS}
	@.plume-scripts/cronic shellcheck -x -P SCRIPTDIR --format=diff ${SH_SCRIPTS} ${BASH_SCRIPTS} | patch -p1
endif
shell-style-check:
ifneq ($(SH_SCRIPTS)$(BASH_SCRIPTS),)
	@.plume-scripts/cronic shfmt -d -i 2 -ci -bn -sr ${SH_SCRIPTS} ${BASH_SCRIPTS}
	@.plume-scripts/cronic shellcheck -x -P SCRIPTDIR --format=gcc ${SH_SCRIPTS} ${BASH_SCRIPTS}
endif
ifneq ($(SH_SCRIPTS),)
	@.plume-scripts/cronic .plume-scripts/checkbashisms -l ${SH_SCRIPTS}
endif
showvars::
	@echo "SH_SCRIPTS=${SH_SCRIPTS}"
	@echo "BASH_SCRIPTS=${BASH_SCRIPTS}"

plume-scripts-update:
	@.plume-scripts-update git -q -C .plume-scripts pull --ff-only
