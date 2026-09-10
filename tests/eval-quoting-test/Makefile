.PHONY: all clean test

all: test

test: ../../ci-info ../../ci-org-and-branch ../../git-changes \
	../../set-ci-org-and-branch ../../set-git-range eval-quoting-test.sh
	./eval-quoting-test.sh

clean:
