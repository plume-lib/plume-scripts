.PHONY: all clean test trace-test temp-file-test

all: test

test: trace-test temp-file-test

trace-test: ../../cronic cronic-test.sh
	./cronic-test.sh

temp-file-test: ../../cronic temp-file-test.sh
	./temp-file-test.sh

clean:
