.PHONY: all clean test

all: test

test: ../../ci-org-and-branch ../../git-changes ../../eval-wrapper.sh \
	../../set-ci-org-and-branch ../../set-git-range missing-file-test.sh
	./missing-file-test.sh

clean:
