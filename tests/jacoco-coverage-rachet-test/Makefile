PROGRAM=../../jacoco-coverage-rachet

test: test12 test21 test13 test31

test12:
	${PROGRAM} jacocoTestReport1.csv jacocoTestReport2.csv > out12.txt
	diff goal12.txt out12.txt

test21:
	${PROGRAM} jacocoTestReport2.csv jacocoTestReport1.csv > out21.txt
	diff goal21.txt out21.txt

test13:
	${PROGRAM} jacocoTestReport1.csv jacocoTestReport3.csv > out13.txt
	diff goal13.txt out13.txt

test31:
	${PROGRAM} jacocoTestReport3.csv jacocoTestReport1.csv > out31.txt
	diff goal31.txt out31.txt



# Miscellaneous targets

# It would be nicer to put all generated files in a subdirectory.
clean:
	rm -f words1.txt words2.txt words12-diff.txt words-lint.txt words2-lint.txt words2-lint-pruned.txt words2-lint-pruned.txt-goal words2-lint.txt-goal-pruned words2-lint.txt-pruned words2-lint-pruned.txt-goal-nofilename words2-lint-pruned.txt-nofilename reldir-lint-pruned.txt guessstrip-lint-pruned.txt javaexception-lint-pruned.txt

