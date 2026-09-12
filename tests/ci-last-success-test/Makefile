.PHONY: all clean test

all: test

# `ci-last-success-test.sh` tests which commits are reported as successful;
# `test-ci-last-success.sh` tests how the GitHub API is used.
test: ../../ci-last-success.py ci-last-success-test.sh test-ci-last-success.sh
	./ci-last-success-test.sh
	./test-ci-last-success.sh

clean:
