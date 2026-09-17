.PHONY: all clean test

all: test

test: ../../ci-info ../../ci-org-and-branch ../../set-ci-org-and-branch \
	github-organization-test.sh
	./github-organization-test.sh

clean:
