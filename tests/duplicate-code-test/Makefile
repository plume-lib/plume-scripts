.PHONY: all clean test

all: test

test: ../../ci-org-and-branch ../../git-changes duplicate-code-test.sh
	./duplicate-code-test.sh

clean:
