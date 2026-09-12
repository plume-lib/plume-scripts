.PHONY: all clean test

all: test

test: ../../preplace preplace-test.sh symlink-test.sh binary-test.sh
	./preplace-test.sh
	./symlink-test.sh
	./binary-test.sh

clean:
