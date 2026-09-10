.PHONY: all clean test

all: test

test: ../../ci-info ../../ci-org-and-branch ../../git-changes \
	../../set-ci-org-and-branch ../../set-git-range jq-null-test.sh
	./jq-null-test.sh

clean:
