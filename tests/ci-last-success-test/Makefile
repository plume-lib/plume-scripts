.PHONY: all clean test

all: test

# `ci-last-success-test.sh` tests which commits are reported as successful;
# `api-usage-test.sh` tests how the GitHub API is used.
test: ../../ci-last-success.py ci-last-success-test.sh api-usage-test.sh
	./ci-last-success-test.sh
	./api-usage-test.sh

clean:
