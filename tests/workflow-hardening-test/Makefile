.PHONY: all clean test

all: test

test: ../../.github/workflows workflow-hardening-test.sh workflow-hardening.awk \
  $(wildcard examples/*)
	./workflow-hardening-test.sh

clean:
