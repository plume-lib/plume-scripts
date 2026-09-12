.PHONY: test clean all

all: test

test: test-words test-reldir test-guessstrip test-javaexception test-incomparable \
  test-mixedpaths test-gradleindent


# "words" test

test-words: words2-lint-pruned.txt-goal-nofilename words2-lint-pruned.txt-nofilename
	diff $^

# words1.txt and words2.txt are subsets of words.txt.
words1.txt: words.txt
	grep -v 'a.*e.*t' $< > $@

words2.txt: words.txt
	grep -v 'a.*a.*e' $< > $@

# Suppose that the edit goes from words1.txt to words2.txt.
words12.diff: words1.txt words2.txt
	diff -u $^ > $@ || true

words-lint.txt: words.txt
	grep -Hn 'a.*i' $< > $@ || true

# Suppose that there are warnings on files with "a.*i".
words2-lint.txt: words2.txt
	grep -Hn 'a.*i' $< > $@ || true

words2-lint-pruned.txt: ../../lint-diff.py words12.diff words2-lint.txt
	../../lint-diff.py --context=0 words12.diff words2-lint.txt > $@ || true

# The goal is lines from words-lint.txt that are in words2.txt but not words1.txt.
# The perl command removes lines that match both a.*e.*t and a.*a.*e .
words2-lint-pruned.txt-goal: words-lint.txt
	grep ':.*a.*e.*t' $< | perl -ni -e 'print unless /a.*e.*t/ && /a.*a.*e/' > $@ || true

%-nofilename: %
	sed 's/^[-A-Za-z0-9.]\{1,\}:[0-9]\{1,\}://' $< > $@


# "reldir" test

test-reldir: reldir-lint-pruned.txt-goal reldir-lint-pruned.txt
	diff $^

reldir-lint-pruned.txt: ../../lint-diff.py reldir.diff reldir-lint.txt
	../../lint-diff.py --strip-diff=1 --strip-lint=2 --context=0 reldir.diff reldir-lint.txt > $@ || true


# "guessstrip" test

test-guessstrip: guessstrip-lint-pruned.txt-goal guessstrip-lint-pruned.txt
	diff $^

guessstrip-lint-pruned.txt: ../../lint-diff.py guessstrip.diff guessstrip-lint.txt
	../../lint-diff.py --guess-strip guessstrip.diff guessstrip-lint.txt > $@ || true

# "javaexception" test

test-javaexception: javaexception-lint-pruned.txt-goal javaexception-lint-pruned.txt
	diff $^

javaexception-lint-pruned.txt: ../../lint-diff.py javaexception.diff javaexception-lint.txt
	../../lint-diff.py --guess-strip javaexception.diff javaexception-lint.txt > $@ || true


# "incomparable" test

# The lint tool reports some paths relative to a module and others relative to
# the repository, so the candidate strip values are not pointwise comparable.
test-incomparable: incomparable-lint-pruned.txt-goal incomparable-lint-pruned.txt
	diff $^

incomparable-lint-pruned.txt: incomparable.diff incomparable-lint.txt ../../lint-diff.py
	../../lint-diff.py --guess-strip --context=0 incomparable.diff incomparable-lint.txt > $@ || true


# "mixedpaths" test

# The lint tool reports some paths relative to the repository and others as
# absolute paths, so they have no common prefix.
test-mixedpaths: mixedpaths-lint-pruned.txt-goal mixedpaths-lint-pruned.txt
	diff $^

# Discard standard error, which contains an expected warning that the diff uses
# relative paths but the lint output uses absolute paths.
mixedpaths-lint-pruned.txt: mixedpaths.diff mixedpaths-lint.txt ../../lint-diff.py
	../../lint-diff.py --guess-strip --context=0 mixedpaths.diff mixedpaths-lint.txt > $@ 2>/dev/null || true


# "gradleindent" test

# After Gradle outputs all warnings, it prints "> Compilation failed; see the
# compiler output below." and then prints one warning, indented by two spaces.
test-gradleindent: gradleindent-lint-pruned.txt-goal gradleindent-lint-pruned.txt
	diff $^

gradleindent-lint-pruned.txt: gradleindent.diff gradleindent-lint.txt ../../lint-diff.py
	../../lint-diff.py --context=0 gradleindent.diff gradleindent-lint.txt > $@ || true


# Miscellaneous targets

# The `clean` target would be simpler if all generated files were put in a subdirectory.
clean:
	rm -f words1.txt words2.txt words12.diff words-lint.txt words2-lint.txt words2-lint-pruned.txt words2-lint-pruned.txt-goal words2-lint.txt-goal-pruned words2-lint.txt-pruned words2-lint-pruned.txt-goal-nofilename words2-lint-pruned.txt-nofilename reldir-lint-pruned.txt guessstrip-lint-pruned.txt javaexception-lint-pruned.txt incomparable-lint-pruned.txt mixedpaths-lint-pruned.txt gradleindent-lint-pruned.txt
