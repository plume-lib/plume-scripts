.PHONY: test clean all

# One line per test directory, iterated over below.
TEST_DIRS = \
	ci-info-test \
	eval-quoting-test \
	jacoco-coverage-ratchet-test \
	lint-diff-test \
	sort-compiler-output-test \
	sort-directory-order-test \
	squeeze-blank-lines-test

all: test

# The recipes loop over ${TEST_DIRS} rather than naming one directory per line,
# because `checkmake` permits at most 5 lines in a recipe.

test:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir test || exit $$? ; done

clean:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir clean || exit $$? ; done
