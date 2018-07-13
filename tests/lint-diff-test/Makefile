test: lint2-pruned.txt-goal-nofilename lint2-pruned.txt-nofilename
	diff $^

clean:
	rm -f words1.txt words2.txt diff.txt lint.txt lint2.txt lint2-pruned.txt lint2-pruned.txt-goal lint2.txt-goal-pruned lint2.txt-pruned lint2-pruned.txt-goal-nofilename lint2-pruned.txt-nofilename

words1.txt: words.txt
	grep -v 'a.*e.*t' $< > $@

words2.txt: words.txt
	grep -v 'a.*a.*e' $< > $@

diff.txt: words1.txt words2.txt
	diff -u $^ > $@ || true

lint.txt: words.txt
	grep -Hn 'a.*i' $< > $@ || true

lint2.txt: words2.txt
	grep -Hn 'a.*i' $< > $@ || true

lint2-pruned.txt: diff.txt lint2.txt
	../../lint-diff.py $^ > $@ || true

# TODO: need to remove lines that match both a.*e.*t and a.*a.*e
lint2-pruned.txt-goal: lint.txt
	grep ':.*a.*e.*t' $< | perl -ni -e 'print unless /a.*e.*t/ && /a.*a.*e/' > $@ || true

%-nofilename: %
	sed 's/^[-A-Za-z0-9.]\{1,\}:[0-9]\{1,\}://' $< > $@
