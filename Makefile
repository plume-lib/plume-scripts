all: test python-style

test:
	${MAKE} -C tests test

PYTHON_FILES=lint-diff.py

python-style:
	yapf -i ${PYTHON_FILES}
	pylint -f parseable --disable=W ${PYTHON_FILES}

