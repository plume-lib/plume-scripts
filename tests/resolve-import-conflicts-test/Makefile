diff: MergedGoal.java Merged.java
	diff -u $^

clean:
	rm -f Merged.java

Merged.java: Parent1.java Base.java Parent2.java
	-git merge-file -q -p $^ > $@
	../../resolve-import-conflicts $@
