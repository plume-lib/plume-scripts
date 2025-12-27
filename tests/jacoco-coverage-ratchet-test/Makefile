PROGRAM=../../jacoco-coverage-ratchet

.PHONY: clean test test12 test21 test13 test31
test: test12 test21 test13 test31

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



# Miscellaneous targets

clean:
	rm -f out12.txt out21.txt out13.txt out31.txt

