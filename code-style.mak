# -*- makefile -*-

###########################################################################
### Documentation
###

# This Makefile fragment defines targets:
# * style-check : runs a linter on all HTML, Markdown, Python, Shell, and YAML
#   files in or under the current.
# * style-fix : fixes linting problems, where possible.  Not all can be fixed.
# * plume-scripts-update : updates the linting rules to the latest version.

# To use it, add these 5 lines to your Makefile:
#
# # Code style; defines `style-check` and `style-fix`.
# ifeq (,$(wildcard .plume-scripts))
# dummy := $(shell git clone -q https://github.com/plume-lib/plume-scripts.git .plume-scripts)
# endif
# include .plume-scripts/code-style.mak
#
# Optionally, to add or remove files from style checking, define one
# or more of these variables, before the above snippet:
#
# SH_SCRIPTS_USER := dots/.aliases dots/.environment dots/.profile
# BASH_SCRIPTS_USER := dots/.bashrc dots/.bash_profile
# CODE_STYLE_EXCLUSIONS_USER := --exclude-dir apheleia --exclude-dir 'apheleia-*' --exclude-dir=mew --exclude=csail-athena-tickets.bash --exclude=conda-initialize.sh --exclude=addrfilter 

# You can disable all style checking by defining environment variable
# CODE_STYLE_DISABLE to any value.

# Requirements/dependencies
#
# You need to install tools depending on what type of files your project contains:
# * must always be installed: `make`
# * for HTML checking: Python, uv
# * for Markdown checking: either of these:
#   * npm, markdownlint-cli2
#   * Python, uv
# * for Perl checking: nothing (Perl checking is currently a no-op)
# * for Python checking: Python, uv
# * for Shell checking: shellcheck, shfmt
#   * to speed up Shell checking, also: bkt
# * for YAML checking: Python, uv

# Instructions for installing these tools:
# * Python is probably already installed on your system
# * [uv](https://docs.astral.sh/uv/#installation)
# * [shellcheck](https://github.com/koalaman/shellcheck#installing)
# * [shfmt](https://webinstall.dev/shfmt/)
# * [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2#install)
# * [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)
# * [bkt](https://github.com/dimo414/bkt#installation)

# Your `.gitignore` file should contain this line:
# .plume-scripts


###########################################################################
### User-overridable variables
###

# Set the variables *before* your makefile includes `code-style.mak`.

ifndef CODE_STYLE_EXCLUSIONS
CODE_STYLE_EXCLUSIONS := --exclude-dir=.do-like-javac --exclude-dir=.git --exclude-dir='.nfs*' --exclude-dir=.plume-scripts --exclude-dir=.venv --exclude-dir=api --exclude-dir=build --exclude='.nfs*' --exclude='\#*' --exclude='*~' --exclude='*.bak' --exclude='*.tar' --exclude='*.tdy' --exclude=gradlew
endif


###########################################################################
### The code
###

.PHONY: style-fix style-check

# This "if" is closed nearly at the end of the file.
ifdef CODE_STYLE_DISABLE
style-check:
	@echo 'Environment var CODE_STYLE_DISABLE is set, so `make style-check` does nothing.'
style-fix:
	@echo 'Environment var CODE_STYLE_DISABLE is set, so `make style-fix` does nothing.'
else # This "else" is closed nearly at the end of the file.

# `checkbashisms` is not included by source because it uses the GPL.
ifeq (,$(wildcard .plume-scripts/checkbashisms))
dummy := $(shell cd .plume-scripts \
   && wget -q -N https://homes.cs.washington.edu/~mernst/software/checkbashisms \
   && chmod +x checkbashisms)
endif
# Install a git pre-commit hook if one doesn't already exist.
ifneq (,$(wildcard .git/hooks))
ifeq (,$(wildcard .git/hooks/pre-commit))
dummy := $(shell cd .git/hooks \
   && ln -s ../../.plume-scripts/code-style-pre-commit pre-commit)
endif
endif

BKT_EXISTS := $(shell if command -v bkt > /dev/null 2>&1; then echo "yes"; fi)
UV_EXISTS := $(shell if command -v uv > /dev/null 2>&1; then echo "yes"; fi)


## HTML
.PHONY: html-style-fix html-style-check
style-fix fix-style: html-style-fix
style-check check-style: html-style-check
ifneq (,${UV_EXISTS})
# Any file ending with ".html".
HTML_FILES   := $(shell grep -r -l --include='*.html' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .)
ifneq (,${HTML_FILES})
# HTML linters are listed in order of increasing precedence.
HTML5VALIDATOR_EXISTS_UVX := $(shell if uvx html5validator --version > /dev/null 2>&1; then echo "yes"; fi)
ifdef HTML5VALIDATOR_EXISTS_UVX
HTML_STYLE_FIX := uvx html5validator fix
HTML_STYLE_CHECK := uvx html5validator scan --show-warnings
HTML_STYLE_VERSION := uvx html5validator --version
endif
HTML5VALIDATOR_EXISTS_UV := $(shell if uv run html5validator --version > /dev/null 2>&1; then echo "yes"; fi)
ifdef HTML5VALIDATOR_EXISTS_UV
HTML_STYLE_FIX := uv run html5validator fix
HTML_STYLE_CHECK := uv run html5validator scan --show-warnings
HTML_STYLE_VERSION := uv run html5validator --version
endif
endif # ifneq (,${HTML_FILES})
endif # ifneq (,${UV_EXISTS})
html-style-fix:
ifneq (,${HTML_FILES})
ifeq (,${UV_EXISTS})
	@echo Skipping html5validator because uv is not installed.
else
ifndef HTML_STYLE_FIX
	@echo Skipping html5validator because it is not installed.
	-uvx html5validator --version
	-uv run html5validator --version
	@false
else
	@.plume-scripts/cronic ${HTML_STYLE_FIX} ${HTML_FILES} || (${HTML_STYLE_VERSION} && false)
endif
endif
endif # ifneq (,${HTML_FILES})
html-style-check:
ifneq (,${HTML_FILES})
ifeq (,${UV_EXISTS})
	@echo Skipping html5validator because uv is not installed.
else
ifndef HTML_STYLE_CHECK
	@echo Cannot find 'uvx html5validator' or 'uv run html5validator'
	-uvx html5validator --version
	-uv run html5validator --version
	@false
else
	@.plume-scripts/cronic ${HTML_STYLE_CHECK} ${HTML_FILES} || (${HTML_STYLE_VERSION} && false)
endif
endif
endif # ifneq (,${HTML_FILES})
showvars::
	@echo "HTML_FILES=${HTML_FILES}"
ifneq (,${HTML_FILES})
	${HTML_STYLE_VERSION}
endif


## Makefiles
# I cannot find any decent Makefile linting tool, that handles
# non-trivial Makefiles (like this one!).  Three inadequate tools
# (best to worst) are:
# https://github.com/EbodShojaei/bake
# https://github.com/checkmake/checkmake
# https://crates.io/crates/unmake


## Markdown
.PHONY: markdown-style-fix markdown-style-check
style-fix: markdown-style-fix
style-check: markdown-style-check
MARKDOWN_FILES   := $(shell grep -r -l --include='*.md' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .)
ifneq (,${MARKDOWN_FILES})
# Markdown linters are listed in order of increasing precedence.
ifneq (,${UV_EXISTS})
PYMARKDOWNLNT_EXISTS_UVX := $(shell if uvx pymarkdownlnt version > /dev/null 2>&1; then echo "yes"; fi)
ifdef PYMARKDOWNLNT_EXISTS_UVX
MARKDOWN_STYLE_FIX := uvx pymarkdownlnt --config .plume-scripts/.pymarkdown fix
MARKDOWN_STYLE_CHECK := uvx pymarkdownlnt --config .plume-scripts/.pymarkdown scan
MARKDOWN_STYLE_VERSION := uvx pymarkdownlnt version
endif
PYMARKDOWNLNT_EXISTS_UV := $(shell if uv run pymarkdownlnt version > /dev/null 2>&1; then echo "yes"; fi)
ifdef PYMARKDOWNLNT_EXISTS_UV
MARKDOWN_STYLE_FIX := uv run pymarkdownlnt --config .plume-scripts/.pymarkdown fix
MARKDOWN_STYLE_CHECK := uv run pymarkdownlnt --config .plume-scripts/.pymarkdown scan
MARKDOWN_STYLE_VERSION := uv run pymarkdownlnt version
endif
endif # ifneq (,${UV_EXISTS})
DOCKER_EXISTS := $(shell if docker --version > /dev/null 2>&1; then echo "yes"; fi)
ifdef DOCKER_EXISTS
# DOCKER_RUNNING := $(shell if curl -s --unix-socket /var/run/docker.sock http/_ping 2>&1 >/dev/null; then echo "yes"; fi)
DOCKER_RUNNING := $(shell if docker version > /dev/null 2>&1; then echo "yes"; fi)
endif
ifdef DOCKER_RUNNING
DMDL := docker run -v $$PWD:/workdir -v $$(readlink -f .plume-scripts):/plume-scripts davidanson/markdownlint-cli2:v0.20.0
MARKDOWN_STYLE_FIX := ${DMDL} --fix --config /plume-scripts/.markdownlint-cli2.yaml "\#node_modules"
MARKDOWN_STYLE_CHECK := ${DMDL} --config /plume-scripts/.markdownlint-cli2.yaml "\#node_modules"
MARKDOWN_STYLE_VERSION := ${DMDL} --help 2>&1 | head -1
# docker run --entrypoint /bin/sh davidanson/markdownlint-cli2:v0.20.0 -c "echo 'hello world'"
$(info About to ls directories)
$(info $(shell docker run --entrypoint /bin/sh -v $$PWD:/workdir -v $$(readlink -f .plume-scripts):/plume-scripts davidanson/markdownlint-cli2:v0.20.0 -c pwd))
$(info $(shell docker run --entrypoint /bin/sh -v $$PWD:/workdir -v $$(readlink -f .plume-scripts):/plume-scripts davidanson/markdownlint-cli2:v0.20.0 -c ls -al /))
$(info $(shell docker run --entrypoint /bin/sh -v $$PWD:/workdir -v $$(readlink -f .plume-scripts):/plume-scripts davidanson/markdownlint-cli2:v0.20.0 -c ls -al /workdir))
$(info $(shell docker run --entrypoint /bin/sh -v $$PWD:/workdir -v $$(readlink -f .plume-scripts):/plume-scripts davidanson/markdownlint-cli2:v0.20.0 -c ls -al /plume-scripts))
endif
MARKDOWNLINT_CLI2_EXISTS := $(shell if markdownlint-cli2 --version > /dev/null 2>&1; then echo "yes"; fi)
ifdef MARKDOWNLINT_CLI2_EXISTS
MARKDOWN_STYLE_FIX := markdownlint-cli2 --fix --config .plume-scripts/.markdownlint-cli2.yaml "\#node_modules"
MARKDOWN_STYLE_CHECK := markdownlint-cli2 --config .plume-scripts/.markdownlint-cli2.yaml "\#node_modules"
MARKDOWN_STYLE_VERSION := markdownlint-cli2 --help | head -1
endif
endif # ifneq (,${MARKDOWN_FILES})
markdown-style-fix:
ifneq (,${MARKDOWN_FILES})
ifndef MARKDOWN_STYLE_FIX
	@echo Cannot find 'uvx pymarkdownlnt' or 'uv run pymarkdownlnt' or 'markdownlint-cli2'
	-uvx pymarkdownlnt version
	-uv run pymarkdownlnt version
	-markdownlint-cli2 --version
else
	@.plume-scripts/cronic ${MARKDOWN_STYLE_FIX} ${MARKDOWN_FILES} || (${MARKDOWN_STYLE_VERSION} && false)
endif
endif # ifneq (,${MARKDOWN_FILES})
markdown-style-check:
ifneq (,${MARKDOWN_FILES})
ifndef MARKDOWN_STYLE_CHECK
	@echo Cannot find 'uvx pymarkdownlnt' or 'uv run pymarkdownlnt' or 'markdownlint-cli2'
	-uvx pymarkdownlnt version
	-uv run pymarkdownlnt version
	-command -v markdownlint-cli2
	@false
else
	@.plume-scripts/cronic ${MARKDOWN_STYLE_CHECK} ${MARKDOWN_FILES} || (${MARKDOWN_STYLE_VERSION} && false)
endif
endif # ifneq (,${MARKDOWN_FILES})
showvars::
	@echo "MARKDOWN_FILES=${MARKDOWN_FILES}"
ifneq (,${MARKDOWN_FILES})
	${MARKDOWN_STYLE_VERSION}
	@echo "DOCKER_EXISTS=${DOCKER_EXISTS}"
ifeq (yes,${DOCKER_EXISTS})
	docker --version
	@echo "DOCKER_RUNNING=${DOCKER_RUNNING}"
endif
	@echo "PYMARKDOWNLNT_EXISTS_UVX=${PYMARKDOWNLNT_EXISTS_UVX}"
	@echo "PYMARKDOWNLNT_EXISTS_UV=${PYMARKDOWNLNT_EXISTS_UV}"
	@echo "MARKDOWN_STYLE_FIX=${MARKDOWN_STYLE_FIX}"
	@echo "MARKDOWN_STYLE_CHECK=${MARKDOWN_STYLE_CHECK}"
	@echo "MARKDOWNLINT_CLI2_EXISTS=${MARKDOWNLINT_CLI2_EXISTS}"
endif


## Perl
.PHONY: perl-style-fix perl-style-check
style-fix: perl-style-fix
style-check: perl-style-check
# Any file ending with ".pl" or ".pm" or containing a Perl shebang line.
PERL_FILES   := $(strip $(shell grep -r -l --include='*.pl' --include='*.pm' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .) $(shell grep -r -l --exclude='*.pl' --exclude='*.pm' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/\|/usr/bin/env \)perl' .))
perl-style-fix:
ifneq (,${PERL_FILES})
# I don't think that perltidy is an improvement.
#	@perltidy -w -b -bext='/' -gnu ${PERL_FILES}
#	@find . -name '*.tdy' -type f -delete
endif
perl-style-check:
ifneq (,${PERL_FILES})
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
PYTHON_FILES:=$(strip $(shell grep -r -l --include='*.py' ${CODE_STYLE_EXCLUSIONS}  ${CODE_STYLE_EXCLUSIONS_USER} '^' .) $(shell grep -r -l --exclude='*.py' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/\|/usr/bin/env \)python' .))
ifneq (,${PYTHON_FILES})
ifneq (,${UV_EXISTS})
RUFF_EXISTS_UVX := $(shell if uvx ruff version > /dev/null 2>&1; then echo "yes"; fi)
ifdef RUFF_EXISTS_UVX
RUFF := uvx ruff
endif
RUFF_EXISTS_UV := $(shell if uv run ruff version > /dev/null 2>&1; then echo "yes"; fi)
ifdef RUFF_EXISTS_UV
RUFF := uv run ruff
endif
TY_EXISTS_UVX := $(shell if uvx ty version > /dev/null 2>&1; then echo "yes"; fi)
ifdef TY_EXISTS_UVX
TY := uvx ty
endif
TY_EXISTS_UV := $(shell if uv run ty version > /dev/null 2>&1; then echo "yes"; fi)
ifdef TY_EXISTS_UV
TY := uv run ty
endif
endif # ifneq (,${UV_EXISTS})
endif # ifneq (,${PYTHON_FILES})
python-style-fix:
ifneq (,${PYTHON_FILES})
ifeq (,${RUFF})
	@echo Skipping ruff because it is not installed.
else
	@.plume-scripts/cronic ${RUFF} format --config .plume-scripts/.ruff.toml ${PYTHON_FILES} || (${RUFF} version && false)
	@.plume-scripts/cronic ${RUFF} check --fix --config .plume-scripts/.ruff.toml ${PYTHON_FILES} || (${RUFF} version && false)
endif
endif
python-style-check:
ifneq (,${PYTHON_FILES})
ifeq (,${RUFF})
	@echo Skipping ruff because it is not installed.
else
	@.plume-scripts/cronic ${RUFF} format --check --config .plume-scripts/.ruff.toml ${PYTHON_FILES} || (${RUFF} version && false)
	@.plume-scripts/cronic ${RUFF} check --config .plume-scripts/.ruff.toml ${PYTHON_FILES} || (${RUFF} version && false)
endif
endif
python-typecheck:
ifneq (,${PYTHON_FILES})
ifeq (,${TY})
	@echo Skipping ty because it is not installed.
else
# Problem: `ty` ignores files passed on the command line that do not end with `.py`.
	@.plume-scripts/cronic ${TY} check --error-on-warning --no-progress ${PYTHON_FILES} || (${TY} version && false)
endif
endif
showvars::
	@echo "PYTHON_FILES=${PYTHON_FILES}"
ifneq (,${PYTHON_FILES})
	@echo "RUFF_EXISTS_UVX=${RUFF_EXISTS_UVX}"
	@echo "RUFF_EXISTS_UV=${RUFF_EXISTS_UV}"
	@echo "RUFF=${RUFF}"
ifdef RUFF
	${RUFF} version
endif
	@echo "TY_EXISTS_UVX=${TY_EXISTS_UVX}"
	@echo "TY_EXISTS_UV=${TY_EXISTS_UV}"
	@echo "TY=${TY}"
ifdef TY
	${TY} version
endif
endif

## Shell
.PHONY: shell-style-fix shell-style-check
style-fix: shell-style-fix
style-check: shell-style-check
# Files ending with ".sh" might be bash or Posix sh, so don't make any assumption about them.
SH_SCRIPTS   := $(strip ${SH_SCRIPTS_USER} $(shell grep -r -l ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/env \)sh' .))
# Any file ending with ".bash" or containing a bash shebang line.
BASH_SCRIPTS := $(strip ${BASH_SCRIPTS_USER} $(shell grep -r -l --include='*.bash' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .) $(shell grep -r -l --exclude='*.bash' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^\#! \?\(/bin/\|/usr/bin/env \)bash' .))
SH_AND_BASH_SCRIPTS := $(strip ${SH_SCRIPTS} ${BASH_SCRIPTS})
ifneq (,${SH_AND_BASH_SCRIPTS})
ifneq (,${BKT_EXISTS})
SHELL_BKT_COMMAND := bkt --cwd $(patsubst %,--modtime %,${SH_AND_BASH_SCRIPTS}) --ttl 1month --
endif
SHFMT_EXISTS := $(shell if shfmt --version > /dev/null 2>&1; then echo "yes"; fi)
SHELLCHECK_EXISTS := $(shell if shellcheck --version > /dev/null 2>&1; then echo "yes"; fi)
endif # ifneq (,$SH_AND_BASH_SCRIPTS)
shell-style-fix:
ifneq (,${SH_AND_BASH_SCRIPTS})
ifeq (,${SHFMT_EXISTS})
	@echo "skipping shfmt because it is not installed"
else
	@${SHELL_BKT_COMMAND} .plume-scripts/cronic shfmt -w -i 2 -ci -bn -sr ${SH_AND_BASH_SCRIPTS} || (shfmt --version && false)
endif
ifeq (,${SHELLCHECK_EXISTS})
	@echo "skipping shellcheck because it is not installed"
else
	@${SHELL_BKT_COMMAND} shellcheck -x -P SCRIPTDIR --format=diff ${SH_AND_BASH_SCRIPTS} | patch -p1 || (shellcheck --version && false)
endif
endif # ifneq (,${SH_AND_BASH_SCRIPTS})
shell-style-check:
ifneq (,${SH_AND_BASH_SCRIPTS})
ifeq (,${SHFMT_EXISTS})
	@echo "skipping shfmt because it is not installed"
else
	@${SHELL_BKT_COMMAND} .plume-scripts/cronic shfmt -d -i 2 -ci -bn -sr ${SH_AND_BASH_SCRIPTS} || (shfmt --version && false)
endif
ifeq (,${SHELLCHECK_EXISTS})
	@echo "skipping shellcheck because it is not installed"
else
	@${SHELL_BKT_COMMAND} .plume-scripts/cronic shellcheck -x -P SCRIPTDIR --format=gcc ${SH_AND_BASH_SCRIPTS} || (shellcheck --version && false)
endif
endif
ifneq (,${SH_SCRIPTS})
	@${SHELL_BKT_COMMAND} .plume-scripts/cronic .plume-scripts/checkbashisms -l ${SH_SCRIPTS}
endif
showvars::
	@echo "SH_SCRIPTS=${SH_SCRIPTS}"
	@echo "BASH_SCRIPTS=${BASH_SCRIPTS}"
ifneq (,${SH_AND_BASH_SCRIPTS})
	@echo "SHFMT_EXISTS=${SHFMT_EXISTS}"
ifneq (,${SHFMT_EXISTS})
	shfmt --version
endif
	@echo "UV_EXISTS=${UV_EXISTS}"
ifneq (,${UV_EXISTS})
	uv --version
endif
	@echo "BKT_EXISTS=${BKT_EXISTS}"
ifneq (,${BKT_EXISTS})
	bkt --version
	@echo "SHELL_BKT_COMMAND=${SHELL_BKT_COMMAND}"
endif
	@echo "SHELLCHECK_EXISTS=${SHELLCHECK_EXISTS}"
ifneq (,${SHELLCHECK_EXISTS})
	shellcheck --version | head -2
endif
endif


## YAML
.PHONY: yaml-style-fix yaml-style-check
style-fix: yaml-style-fix
style-check: yaml-style-check
# Any file ending with ".yaml" or ".yml".
YAML_FILES   := $(shell grep -r -l --include='*.yaml' --include='*.yml' ${CODE_STYLE_EXCLUSIONS} ${CODE_STYLE_EXCLUSIONS_USER} '^' .)
ifneq (,${YAML_FILES})
# YAML linters are listed in order of increasing precedence.
YAMLLINT_EXISTS := $(shell if yamllint --version > /dev/null 2>&1; then echo "yes"; fi)
ifneq (,${YAMLLINT_EXISTS})
YAMLLINT := yamllint
endif
ifneq (,${UV_EXISTS})
PYYAMLLNT_EXISTS_UVX := $(shell if uvx yamllint --version > /dev/null 2>&1; then echo "yes"; fi)
ifdef PYYAMLLNT_EXISTS_UVX
YAMLLINT := uvx yamllint
endif
PYYAMLLNT_EXISTS_UV := $(shell if uv run yamllint --version > /dev/null 2>&1; then echo "yes"; fi)
ifdef PYYAMLLNT_EXISTS_UV
YAMLLINT := uv run yamllint
endif
endif # ifneq (,${UV_EXISTS})
endif # ifneq (,${YAML_FILES})
yaml-style-fix:
ifneq (,${YAML_FILES})
endif
yaml-style-check:
ifneq (,${YAML_FILES})
ifeq (,${YAMLLINT})
	@echo "skipping yamllint because it is not installed"
else
	@.plume-scripts/cronic ${YAMLLINT} -c .plume-scripts/.yamllint.yaml --format parsable ${YAML_FILES} || (${YAMLLINT} --version && false)
endif
endif
showvars::
	@echo "YAML_FILES=${YAML_FILES}"
	@echo "YAMLLINT=${YAMLLINT}"
ifneq (,${YAMLLINT})
	${YAMLLINT} --version
endif


endif # ifdef CODE_STYLE_DISABLE


plume-scripts-update update-plume-scripts:
	@.plume-scripts/cronic git -C .plume-scripts pull -q --ff-only
