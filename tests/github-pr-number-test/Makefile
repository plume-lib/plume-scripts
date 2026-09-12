.PHONY: all clean test

all: test

test: ../../ci-org-and-branch ../../set-ci-org-and-branch \
	github-pr-number-test.sh
	./github-pr-number-test.sh

clean:
