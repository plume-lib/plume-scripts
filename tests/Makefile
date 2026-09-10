.PHONY: test clean all

all: test

TEST_DIRS = \
  ci-info-test \
  jacoco-coverage-ratchet-test \
  lint-diff-test \
  sort-compiler-output-test \
  sort-directory-order-test \
  squeeze-blank-lines-test

# The recipes loop over ${TEST_DIRS} rather than naming one directory per line,
# because `checkmake` permits at most 5 lines in a recipe.

test:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir test || exit 1; done

clean:
	for dir in ${TEST_DIRS}; do ${MAKE} -C $$dir clean || exit 1; done
