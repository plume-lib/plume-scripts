.PHONY: test clean all

all: test

test: ../../ci-info ../../git-changes ../../set-git-range \
	test-ci-info.sh ci-info-shim-test.sh
	./test-ci-info.sh
	./ci-info-shim-test.sh

clean:
