.PHONY: all clean test

all: test

test: ../../set-ci-org-and-branch ../../set-git-range set-git-range-test.sh azure-shallow-test.sh
	./set-git-range-test.sh
	./azure-shallow-test.sh

clean:
