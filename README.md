# Plume-Scripts:  Scripts for programming and system administration #

I find these scripts automate tedious tasks and speed up my work.
Some were written by me, others were found on the Internet.
Maybe they will help you too.


## cronic

A small shim shell script for wrapping cron jobs so that cron only sends
email when an error has occurred.  Documentation
[at top of file](cronic) and at
http://habilis.net/cronic/.


## Cygwin wrappers

### cygwin-runner

Takes a command with arguments and translates those arguments from
Cygwin-style filenames into Windows-style filenames.  Its real advantage
is the little bit of intelligence it has as far as which things are files
and which are not.
[Documentation](cygwin-runner) at top of file.

### java-cygwin

A wrapper for calling Java from Cygwin, that tries to convert any
arguments that are Unix-style paths into Windows-style paths.
[Documentation](java-cygwin) at top of file.

### javac-cygwin

A wrapper for calling the Java compiler from Cygwin, that tries to convert any
arguments that are Unix-style paths into Windows-style paths.
[Documentation](javac-cygwin) at top of file.

### javadoc-cygwin

A wrapper for calling Javadoc from Cygwin, that tries to convert any
arguments that are Unix-style paths into Windows-style paths.
[Documentation](javadoc-cygwin) at top of file.


## ediff-merge-script

A script for use as a git mergetool; runs Emacs ediff as the mergetool.
[Documentation](ediff-merge-script) at top of file.


## latex-process-inputs

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


## lint-diff.py

Filter the ouput of tools such as lint, to only show output for changed
lines in a diff or pull request.
[Documentation](lint-diff.py) at top of file.


## mail-e

Reads standard input, and if not empty calls the `mail` program on it.
In other words, acts like `mail -e` and isuseful when your version of `mail` does not support `-e`.
This feature is useful in scripts and cron jobs, but is not supported
in all versions of `mail`.
[Documentation](mail-e)
at top of file.


## path-remove

Cleans up a path environment variable by removing duplicates and
non-existent directories.
Can optionally remove certain path elements.
Works for either space- or colon- delimiated paths.
[Documentation](path-remove) at top of file.


## preplace

Replace all matching regular expressions in the given files (or all files
under the current directory).  The timestamp on each file is updated only
if the replacement is performed.
[Documentation](preplace) at top of file.


## search

Jeffrey Friedl's search program combines `find` and `grep`
-- more or less do a 'grep' on a whole directory tree, but is more
efficient, uses Perl regular expressions, and is much more powerful.
This version fixes a tiny bug or two.  For full documentation, see its
[manpage](search.manpage).
This program has been largely superseded by [`ag`](http://geoff.greer.fm/ag/), [`pt`](https://github.com/monochromegane/the_platinum_searcher), etc.  However,
it is still useful because it searches more thoroughly:  in git-ignored
files, and in compressed archives.


## sort-directory-order

Sorts the input lines by directory order:  first, every file in a given
directory, in sorted order; then, process subdirectories recursively, in
sorted order. This is useful for users (e.g., when printing) and for making
output deterministic.
[Documentation](sort-directory-order) at top of file.

