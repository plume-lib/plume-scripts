.PHONY: test clean

test: lines1.output lines1.output2 lines2.output
	diff -u lines1.output-goal lines1.output
	diff -u lines1.output-goal lines1.output2
	diff -u lines2.output-goal lines2.output

lines1.output: ../../squeeze-blank-lines lines1.txt
	../../squeeze-blank-lines < lines1.txt > $@

lines1.output2: ../../squeeze-blank-lines lines1.txt
	cp lines1.txt lines1.output2
	../../squeeze-blank-lines lines1.output2

lines2.output: ../../squeeze-blank-lines lines2.txt
	../../squeeze-blank-lines < lines2.txt > $@

clean:
	rm -f lines1.output lines1.output2 lines2.output
