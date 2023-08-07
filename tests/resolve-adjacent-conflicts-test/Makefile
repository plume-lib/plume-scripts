diff: MergedGoal.java Merged.java
	diff -u $^

clean:
	rm -f Merged.java

.PHONY: Merged.java
Merged.java: Parent1.java Base.java Parent2.java
	-git merge-file -q  -p $^ > $@
	../../resolve-adjacent-conflicts $@

.PHONY: resolve
resolve:
	mv -f MergedByGit.java Merged.java
	../../resolve-adjacent-conflicts Merged.java

MergedByGit.java: Parent1.java Base.java Parent2.java
	-git merge-file -q  -p $^ > $@
