all: test python-style

test:
	${MAKE} -C tests test

PYTHON_FILES=lint-diff.py

python-style:
	yapf -i --style='{column_limit: 100}' ${PYTHON_FILES}
	pylint -f parseable --disable=W,invalid-name ${PYTHON_FILES}

