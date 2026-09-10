.PHONY: test clean all

# One line per test directory, iterated over below.  A loop rather than one
# recipe line per directory, because `checkmake` permits at most 5 lines in a
# recipe.
# There is exactly one assignment to TEST_DIRS:  a second one would silently
# override this one, and the test directories it omitted would stop running.
TEST_DIRS = \
	ci-info-test \
	eval-quoting-test \
	github-ref-name-test \
	jacoco-coverage-ratchet-test \
	lint-diff-test \
	sort-compiler-output-test \
	sort-directory-order-test \
	squeeze-blank-lines-test

all: test

test:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir test || exit $$? ; done

clean:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir clean || exit $$? ; done
