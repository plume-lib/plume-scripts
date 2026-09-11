.PHONY: all clean test

all: test

test: ../../set-ci-org-and-branch http-status-test.sh
	./http-status-test.sh

clean:
