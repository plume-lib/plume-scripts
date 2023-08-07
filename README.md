# Plume-Scripts:  Scripts for programming and system administration #

These scripts automate various programming and sysadmin tasks.
This project contains utilities for

 * [Shell scripting](#shell-scripting)
 * [Continuous integration](#continuous-integration)
 * [Git](#git)
 * [Search and replace](#search-and-replace)
 * [Sorting](#sorting)
 * [Java](#java)
 * [LaTeX](#latex)


## Installation

To install, run the following (or put it at the top of a script).
Then, the scripts are available at `/tmp/$USER/plume-scripts`.

```
if [ -d /tmp/$USER/plume-scripts ] ; then
  git -C /tmp/$USER/plume-scripts pull -q > /dev/null 2>&1
else
  mkdir -p /tmp/$USER && git -C /tmp/$USER clone --depth 1 -q https://github.com/plume-lib/plume-scripts.git
fi
```

If you want to use a specific version of `plume-scripts` rather than the
bleeding-edge HEAD, you can run `git checkout _SHA_` after the `git clone`
command.


## Shell scripting

### cronic

A wrapper for cron jobs so that cron only sends
email when an error has occurred.
Documentation [at top of file](cronic) and at http://habilis.net/cronic/.

### lint-diff.py

Filter the ouput of tools such as `lint`, to only show output for changed
lines in a diff or pull request.
[Documentation](lint-diff.py) at top of file.

### mail-e

Reads standard input, and if not empty calls the `mail` program on it.
In other words, acts like `mail -e` and isuseful when your version of `mail` does not support `-e`.
This feature is useful in scripts and cron jobs, but is not supported
in all versions of `mail`.
[Documentation](mail-e)
at top of file.

### path-remove

Cleans up a path environment variable by removing duplicates and
non-existent directories.
Can optionally remove certain path elements.
Works for either space- or colon- delimiated paths.
[Documentation](path-remove) at top of file.


## Continuous integration

### ci-info

Obtains information about a CI (continuous integration) job, such as the
organization, the branch, the range of commits, and whether it is a pull
request.  Works for Azure Pipelines, CircleCI, GitHub Actions, and Travis CI.
[Documentation](ci-info) at top of file.

### ci-lint-diff

Given a file of warnings (such as those output by `lint` or other tools),
reports only those that are in the diff for the current pull request.
Works for Azure Pipelines, CircleCI, GitHub Actions, and Travis CI.
[Documentation](ci-lint-diff) at top of file.

### ci-last-success.py

Prints the SHA commit id corresponding to the most recent successful CI job.
[Documentation](ci-last-success.py) at top of file.


## Git

### ediff-merge-script

A script for use as a git mergetool; runs Emacs ediff as the mergetool.
[Documentation](ediff-merge-script) at top of file.

### git-authors

Lists all the authors of commits in a get repository.
[Documentation](git-authors) at top of file.

### git-clone-related

Clones a repository related to the one where this script is called, trying
to match the fork and branch.
Works for Azure Pipelines, CircleCI, GitHub Actions, and Travis CI.
[Documentation](git-clone-related) at top of file.

Suppose you have two related Git repositories:\
  *MY-ORG*`/`*MY-REPO*\
  *MY-ORG*`/`*MY-OTHER-REPO*

In a CI job that is testing branch BR in fork F of *MY-REPO*,
you would like to use fork F of *MY-OTHER-REPO* if it exists,
and you would like to use branch BR if it exists.
Here is how to accomplish that:

```
  if [ -d "/tmp/$USER/plume-scripts" ] ; then
    git -C /tmp/$USER/plume-scripts pull -q > /dev/null 2>&1
  else
    mkdir -p /tmp/$USER && git -C /tmp/$USER clone --depth 1 -q https://github.com/plume-lib/plume-scripts.git
  fi
  /tmp/$USER/plume-scripts/git-clone-related codespecs fjalar
```

### git-find-fork

Finds a fork of a GitHub repository, or returns the upstream repository
if the fork does not exist.
[Documentation](git-find-fork) at top of file.

### git-find-branch

Tests whether a branch exists in a Git repository;
prints the branch, or prints "master" if the branch does not exist.
[Documentation](git-find-branch) at top of file.

### resolve-import-conflicts

Edits files in place to resolves git conflicts that arise from Java `import`
statements.
[Documentation](resolve-import-conflicts) at top of file.

### resolve-adjacent-conflicts

Edits files in place to resolves git conflicts that arise from edits to
adjacent lines.
[Documentation](resolve-adjacent-conflicts) at top of file.


## Search and replace

### preplace

Replace all matching regular expressions in the given files (or all files
under the current directory).  The timestamp on each file is updated only
if the replacement is performed.
[Documentation](preplace) at top of file.


### search

Jeffrey Friedl's search program combines `find` and `grep`
-- more or less do a 'grep' on a whole directory tree, but is more
efficient, uses Perl regular expressions, and is much more powerful.
This version fixes a tiny bug or two.  For full documentation, see its
[manpage](search.manpage).

This program has been largely superseded by
[`rg`](https://github.com/BurntSushi/ripgrep), and before that by
[`pt`](https://github.com/monochromegane/the_platinum_searcher) and
[`ag`](http://geoff.greer.fm/ag/).  However, it is still useful because it
searches more thoroughly:  in git-ignored files, and in compressed
archives.


## Sorting

### sort-directory-order

Sorts the input lines by directory order:  first, every file in a given
directory, in sorted order; then, process subdirectories recursively, in
sorted order. This is useful for users (e.g., when printing) and for making
output deterministic.
[Documentation](sort-directory-order) at top of file.


### sort-compiler-output

Sorts the input errors/warnings by filename.  Works for any tool that produces
output in the [standard
format](https://www.gnu.org/prep/standards/html_node/Errors.html).  This is
useful for compilers such as javac that process files in nondeterministic order.
[Documentation](sort-compiler-output) at top of file.


## Java

### classfile_check_version

Check that a class file's version is &leq; the specified version.
This ensures that the class will run on a particular version of Java.
Documentation [at top of file](classfile_check_version).


## LaTeX

### latex-process-inputs

Determines all files that are recursively `\input` by a given
LaTeX file.
[Documentation](latex-process-inputs) at top of file.
The program has two modes:

 * Inline mode (the default):  Create a single LaTeX file for the document,
   by inlining `\input` commands and removing comments.
   The result is appropriate to be sent to a publisher.
 * List mode: List all the files that are (transitively) `\input`.
   This can be useful for getting a list of source files in a logical order,
   for example to be used in a Makefile or Ant buildfile.
