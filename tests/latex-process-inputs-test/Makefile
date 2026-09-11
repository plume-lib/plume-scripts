.PHONY: test clean all

all: test

INPUTS = main.tex intro.tex code.c snippet.tex

test: inline.actual list.actual
	diff -u inline.goal inline.actual
	diff -u list.goal list.actual

# Verbatim-included text must be passed through unchanged:  neither its "%"
# characters nor its \input commands are processed.
inline.actual: ../../latex-process-inputs ${INPUTS}
	../../latex-process-inputs main.tex > $@

list.actual: ../../latex-process-inputs ${INPUTS}
	../../latex-process-inputs --list main.tex > $@

clean:
	rm -f inline.actual list.actual
