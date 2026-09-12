#!/bin/sh

# Tests `latex-process-inputs`, in both of its modes:
#  * inline mode, which splices each \input file into the document and blanks
#    out comments, and
#  * list mode (--list, --antlist, --makefilelist), which reports the
#    transitively \input files.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
LPI="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/latex-process-inputs"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

status=0

# check_equal DESCRIPTION EXPECTED ACTUAL: reports whether two strings match.
check_equal() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    echo "  expected: <<$2>>"
    echo "  actual:   <<$3>>"
    status=1
  fi
}

# check_fails DESCRIPTION PATTERN COMMAND...: checks that COMMAND exits
# nonzero and that its output contains PATTERN.  Checking the message, not
# merely the status, ensures that the command failed for the intended reason.
check_fails() {
  description="$1"
  pattern="$2"
  shift 2
  actual_status=0
  output="$("$@" 2>&1)" || actual_status=$?
  if [ "$actual_status" = 0 ]; then
    echo "FAIL: $description: expected a nonzero exit status"
    status=1
    return
  fi
  case "$output" in
    *"$pattern"*)
      echo "PASS: $description"
      ;;
    *)
      echo "FAIL: $description: output does not contain '$pattern':"
      echo "$output"
      status=1
      ;;
  esac
}

cd "$work"

## A document with nested \input commands and with comments.

cat > main.tex <<'EOF'
\documentclass{article}
\begin{document}
% a whole-line comment
Hello.  % a trailing comment
100\% sure.
\input{sec1}
\input{sec2.tex}
\end{document}
EOF
cat > sec1.tex <<'EOF'
Section one.
% a comment in an inputted file
EOF
cat > sec2.tex <<'EOF'
Section two.
\input{sec3}
EOF
cat > sec3.tex <<'EOF'
Section three.
EOF

# List mode reports each file once, in the order it is first \input, starting
# with the top-level file.
check_equal "--list" "main.tex
sec1.tex
sec2.tex
sec3.tex" "$("$LPI" --list main.tex)"

# The single-hyphen spelling is accepted too.
check_equal "-list" "main.tex
sec1.tex
sec2.tex
sec3.tex" "$("$LPI" -list main.tex)"

check_equal "--antlist" '      <arg value="main.tex"/>
      <arg value="sec1.tex"/>
      <arg value="sec2.tex"/>
      <arg value="sec3.tex"/>' "$("$LPI" --antlist main.tex)"

check_equal "--makefilelist" 'main.tex \
sec1.tex \
sec2.tex \
sec3.tex' "$("$LPI" --makefilelist main.tex)"

# Inline mode splices in each \input file and replaces every comment by an
# empty comment, keeping the text before the "%".  An escaped "\%" is not a
# comment and must survive.
cat > inline.goal <<'EOF'
\documentclass{article}
\begin{document}
%
Hello.  %
100\% sure.
Section one.
%

Section two.
Section three.


\end{document}
EOF
"$LPI" main.tex > inline.actual
if diff -u inline.goal inline.actual; then
  echo "PASS: inline mode"
else
  echo "FAIL: inline mode"
  status=1
fi

# The comment text itself must not appear in the output; that is the stated
# purpose of blanking comments before sending the file to a publisher.
case "$(cat inline.actual)" in
  *"a whole-line comment"* | *"a trailing comment"* | *"a comment in an inputted file"*)
    echo "FAIL: inline mode leaks comment text"
    status=1
    ;;
  *)
    echo "PASS: inline mode leaks no comment text"
    ;;
esac

## Verbatim inclusion.

cat > verbatim.tex <<'EOF'
\documentclass{article}
\begin{document}
\verbatiminput{code.txt}
\lstinputlisting{code.txt}
\end{document}
EOF
# Verbatim-included text is passed through unchanged:  neither its "%"
# characters nor its \input commands are processed.  `notinputted.tex` exists,
# so if the \input below were processed its contents would be spliced in.
cat > code.txt <<'EOF'
int x = 1;  % not a comment
\input{notinputted}
return x;
EOF
cat > notinputted.tex <<'EOF'
This text must not appear in the output.
EOF

cat > verbatim.goal <<'EOF'
\documentclass{article}
\begin{document}
\begin{verbatim}
int x = 1;  % not a comment
\input{notinputted}
return x;
\end{verbatim}

\begin{lstlisting}
int x = 1;  % not a comment
\input{notinputted}
return x;
\end{lstlisting}

\end{document}
EOF
"$LPI" verbatim.tex > verbatim.actual
if diff -u verbatim.goal verbatim.actual; then
  echo "PASS: verbatiminput and lstinputlisting"
else
  echo "FAIL: verbatiminput and lstinputlisting"
  status=1
fi

# A verbatim-included file is listed like any other input.
check_equal "--list with verbatiminput" "verbatim.tex
code.txt
code.txt" "$("$LPI" --list verbatim.tex)"

## The bibliography is replaced by the contents of the .bbl file.

cat > bib.tex <<'EOF'
\documentclass{article}
\begin{document}
Text.
\bibliography{refs}
\end{document}
EOF
cat > bib.bbl <<'EOF'
\begin{thebibliography}{1}
\bibitem{a} An item.
\end{thebibliography}
EOF
cat > bib.goal <<'EOF'
\documentclass{article}
\begin{document}
Text.
\begin{thebibliography}{1}
\bibitem{a} An item.
\end{thebibliography}

\end{document}
EOF
"$LPI" bib.tex > bib.actual
if diff -u bib.goal bib.actual; then
  echo "PASS: the bibliography is inlined"
else
  echo "FAIL: the bibliography is inlined"
  status=1
fi

# List mode does not need the .bbl file, because it does not inline it.
cp bib.tex nobbl.tex
check_equal "--list does not require a .bbl file" "nobbl.tex" "$("$LPI" --list nobbl.tex)"

## Error cases.

check_fails "a missing .bbl file is an error" \
  'Run bibtex (didn'\''t find bbl file "nobbl.bbl")' "$LPI" nobbl.tex
printf '\\input{nosuchfile}\n' > missinginput.tex
check_fails "a missing input file is an error" \
  "File does not exist: nosuchfile.tex or nosuchfile" "$LPI" missinginput.tex
check_fails "a missing top-level file is an error" \
  "Can't open nosuchfile.tex: No such file or directory" "$LPI" nosuchfile.tex
check_fails "more than one file is an error" \
  "Supply exactly one file on the command line (got 2: main.tex sec1.tex)" \
  "$LPI" main.tex sec1.tex

# With no arguments the script dies while opening the empty filename.  The
# message is unhelpful, but pinning it here means a change to it is noticed.
check_fails "no arguments is an error" \
  "Can't open : No such file or directory" "$LPI"

## --help

actual_status=0
help_output="$("$LPI" --help 2>&1)" || actual_status=$?
check_equal "--help exits 0" "0" "$actual_status"
case "$help_output" in
  *-list*)
    echo "PASS: --help mentions -list"
    ;;
  *)
    echo "FAIL: --help does not mention -list; got: $help_output"
    status=1
    ;;
esac

exit "$status"
