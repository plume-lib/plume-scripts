.PHONY: all clean test

PROGRAM=../../jacoco-coverage-ratchet

all: test

.PHONY: clean test test12 test21 test13 test31 test45 test54 test45ignore
test: test12 test21 test13 test31 test45 test54 test45ignore

test12:
	${PROGRAM} jacocoTestReport1.csv jacocoTestReport2.csv > out12.txt
	diff goal12.txt out12.txt

test21:
	if ${PROGRAM} jacocoTestReport2.csv jacocoTestReport1.csv > out21.txt; then echo "status 1 expected"; false ; fi
	diff goal21.txt out21.txt

test13:
	if ${PROGRAM} jacocoTestReport1.csv jacocoTestReport3.csv > out13.txt; then echo "status 1 expected"; false; fi
	diff goal13.txt out13.txt

test31:
	${PROGRAM} jacocoTestReport3.csv jacocoTestReport1.csv > out31.txt
	diff goal31.txt out31.txt


# A class in the old report but not in the new one is a ratchet failure.
test45:
	if ${PROGRAM} jacocoTestReport4.csv jacocoTestReport5.csv > out45.txt; then echo "status 1 expected"; false; fi
	diff goal45.txt out45.txt

# A class in the new report but not in the old one is fine.
test54:
	${PROGRAM} jacocoTestReport5.csv jacocoTestReport4.csv > out54.txt
	diff goal54.txt out54.txt

# With --ignore-removed-classes, a class in the old report but not in the new
# one is fine.
test45ignore:
	${PROGRAM} --ignore-removed-classes jacocoTestReport4.csv jacocoTestReport5.csv > out45ignore.txt
	diff goal45ignore.txt out45ignore.txt


# Miscellaneous targets

clean:
	rm -f out12.txt out21.txt out13.txt out31.txt out45.txt out54.txt out45ignore.txt
