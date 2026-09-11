.PHONY: test clean all

# One line per test directory, iterated over below.  A loop rather than one
# recipe line per directory, because `checkmake` permits at most 5 lines in a
# recipe.
TEST_DIRS = \
	ci-info-test \
	cronic-test \
	eval-quoting-test \
	github-ref-name-test \
	jacoco-coverage-ratchet-test \
	jq-null-test \
	latex-process-inputs-test \
	lint-diff-test \
	missing-file-test \
	path-remove-test \
	preplace-test \
	sort-compiler-output-test \
	sort-directory-order-test \
	squeeze-blank-lines-test

all: test

test:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir test || exit $$? ; done

clean:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir clean || exit $$? ; done
