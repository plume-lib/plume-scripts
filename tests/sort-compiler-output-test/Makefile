.PHONY: test clean all

all: test

test: errors1-sorted.actual errors2-sorted.actual errors3-sorted.actual \
	errors3-duplicates.actual
	diff errors1-sorted.goal errors1-sorted.actual
	diff errors2-sorted.goal errors2-sorted.actual
	diff errors3-sorted.goal errors3-sorted.actual
	diff errors3-duplicates.goal errors3-duplicates.actual

errors1-sorted.actual: ../../sort-compiler-output errors1.txt
	../../sort-compiler-output < errors1.txt > $@

errors2-sorted.actual: ../../sort-compiler-output errors2.txt
	../../sort-compiler-output < errors2.txt > $@

errors3-sorted.actual: ../../sort-compiler-output errors3.txt
	../../sort-compiler-output < errors3.txt > $@

errors3-duplicates.actual: ../../sort-compiler-output errors3.txt
	../../sort-compiler-output --keep-duplicates < errors3.txt > $@

clean:
	rm -f errors1-sorted.actual errors2-sorted.actual errors3-sorted.actual
	rm -f errors3-duplicates.actual
