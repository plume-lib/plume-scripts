.PHONY: all clean test

all: test

test: ../../ci-info ../../set-ci-org-and-branch ../../set-git-range redact-tokens-test.sh
	./redact-tokens-test.sh

clean:
