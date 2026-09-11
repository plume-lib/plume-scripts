.PHONY: all clean test

all: test

# No prerequisites naming the files under test:  this test checks every file
# that Git tracks, and a list here would go stale.
test: tmp-directory-test.sh
	./tmp-directory-test.sh

clean:
