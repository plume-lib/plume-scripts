test: test-words test-reldir


# "words" test

test-words: words2-lint-pruned.txt-goal-nofilename words2-lint-pruned.txt-nofilename
	diff $^

words1.txt: words.txt
	grep -v 'a.*e.*t' $< > $@

words2.txt: words.txt
	grep -v 'a.*a.*e' $< > $@

words12-diff.txt: words1.txt words2.txt
	diff -u $^ > $@ || true

words-lint.txt: words.txt
	grep -Hn 'a.*i' $< > $@ || true

words2-lint.txt: words2.txt
	grep -Hn 'a.*i' $< > $@ || true

words2-lint-pruned.txt: words12-diff.txt words2-lint.txt
	../../lint-diff.py $^ > $@ || true

# perl command removes lines that match both a.*e.*t and a.*a.*e .
words2-lint-pruned.txt-goal: words-lint.txt
	grep ':.*a.*e.*t' $< | perl -ni -e 'print unless /a.*e.*t/ && /a.*a.*e/' > $@ || true

%-nofilename: %
	sed 's/^[-A-Za-z0-9.]\{1,\}:[0-9]\{1,\}://' $< > $@


# "reldir" test

test-reldir: reldir-lint-pruned.txt-goal reldir-lint-pruned.txt
	diff $^

reldir-lint-pruned.txt: reldir-words12-diff.txt reldir-lint.txt
	../../lint-diff.py --strip-diff=1 --strip-lint=2 $^ > $@ || true


# Miscellaneous targets

# It would be nicer to put all generated files in a subdirectory.
clean:
	rm -f words1.txt words2.txt words12-diff.txt words-lint.txt words2-lint.txt words2-lint-pruned.txt words2-lint-pruned.txt-goal words2-lint.txt-goal-pruned words2-lint.txt-pruned words2-lint-pruned.txt-goal-nofilename words2-lint-pruned.txt-nofilename reldir-lint-pruned.txt

