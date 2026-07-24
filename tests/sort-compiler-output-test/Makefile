.PHONY: test clean all

all: test

test: clean errors1-sorted.actual errors2-sorted.actual
	diff errors1-sorted.goal errors1-sorted.actual
	diff errors2-sorted.goal errors2-sorted.actual

errors1-sorted.actual: ../../sort-compiler-output
	../../sort-compiler-output < errors1.txt > $@

errors2-sorted.actual: ../../sort-compiler-output
	../../sort-compiler-output < errors2.txt > $@

clean:
	rm -f errors1-sorted.actual errors2-sorted.actual
