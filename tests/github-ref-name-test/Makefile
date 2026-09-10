.PHONY: all clean test

all: test

test: ../../ci-info ../../ci-org-and-branch ../../set-ci-org-and-branch \
	github-ref-name-test.sh
	./github-ref-name-test.sh

clean:
