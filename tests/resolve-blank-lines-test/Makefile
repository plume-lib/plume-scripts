PROGRAM=../../resolve-blank-lines

test: diff

diff: MergedGoal.java Merged.java
	diff -u $^

clean:
	rm -f Merged.java MergedByGit.java

.PHONY: Merged.java
Merged.java: Parent1.java Base.java Parent2.java
	-git merge-file -q -p $^ > $@
	-${PROGRAM} $@

.PHONY: resolve
resolve:
	mv -f MergedByGit.java Merged.java
	-${PROGRAM} Merged.java

MergedByGit.java: Parent1.java Base.java Parent2.java
	-git merge-file -q  -p $^ > $@
