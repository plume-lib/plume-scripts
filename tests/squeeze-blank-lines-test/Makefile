.PHONY: test clean all

all: test

test: lines1.output lines1.output2 lines2.output blank.output
	diff -u lines1.output-goal lines1.output
	diff -u lines1.output-goal lines1.output2
	diff -u lines2.output-goal lines2.output
	test ! -s blank.output

lines1.output: ../../squeeze-blank-lines lines1.txt
	../../squeeze-blank-lines < lines1.txt > $@

lines1.output2: ../../squeeze-blank-lines lines1.txt
	cp lines1.txt lines1.output2
	../../squeeze-blank-lines lines1.output2

lines2.output: ../../squeeze-blank-lines lines2.txt
	../../squeeze-blank-lines < lines2.txt > $@

# An empty or all-blank input must produce empty output, not a lone blank line.
blank.output: ../../squeeze-blank-lines blank.txt
	../../squeeze-blank-lines < blank.txt > $@

clean:
	rm -f lines1.output lines1.output2 lines2.output blank.output
