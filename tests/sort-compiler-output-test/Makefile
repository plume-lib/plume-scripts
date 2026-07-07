.PHONY: test clean

test: clean errors1-sorted.actual
	diff errors1-sorted.goal errors1-sorted.actual

errors1-sorted.actual: ../../sort-compiler-output
	../../sort-compiler-output < errors1.txt > $@

clean:
	rm -f errors1-sorted.actual
