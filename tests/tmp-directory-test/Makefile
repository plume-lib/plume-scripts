.PHONY: all clean test

all: test

test: ../../README.md ../../ci-info ../../ci-org-and-branch ../../git-changes \
	../../set-ci-org-and-branch ../../set-git-range tmp-directory-test.sh
	./tmp-directory-test.sh

clean:
