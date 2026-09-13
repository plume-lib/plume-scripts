#!/bin/sh

# Tests `mail-e`:  a version of `mail` that does not send a message when the
# body read from standard input is empty.
#
# The tests put a stub `mail` first on PATH, which records its arguments and
# its standard input, so that nothing is actually sent.

set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
MAIL_E="$(CDPATH='' cd -- "${SCRIPT_DIR}/../.." && pwd -P)/mail-e"

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

# A stub `mail` that records how it was called.  It writes one argument per
# line to $work/args and its standard input to $work/body, and exits with the
# status in $work/mail-exit-status.
mkdir "$work/bin"
cat > "$work/bin/mail" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "${MAIL_E_TEST_DIR}/args"
# Record what $TMPDIR holds while `mail-e` is running, so that a test can tell
# whether the temporary file was created there.
ls "${MAIL_E_TEST_DIR}/tmpdir" > "${MAIL_E_TEST_DIR}/tmpdir-during" 2> /dev/null
cat > "${MAIL_E_TEST_DIR}/body"
exit "$(cat "${MAIL_E_TEST_DIR}/mail-exit-status")"
EOF
chmod +x "$work/bin/mail"

MAIL_E_TEST_DIR="$work"
export MAIL_E_TEST_DIR
PATH="$work/bin:$PATH"
export PATH

# A non-empty body is passed to `mail`, along with `mail`'s arguments.
echo 0 > "$work/mail-exit-status"
rm -f "$work/args" "$work/body"
actual_status=0
printf 'the body\n' | "$MAIL_E" -s "The subject" someone@example.com || actual_status=$?
check_equal "a non-empty body exits 0" "0" "$actual_status"
check_equal "arguments are passed through" "-s
The subject
someone@example.com" "$(cat "$work/args")"
check_equal "the body is passed through" "the body" "$(cat "$work/body")"

# A body with no trailing newline is still sent, and is not truncated.
rm -f "$work/args" "$work/body"
printf 'no trailing newline' | "$MAIL_E" someone@example.com
check_equal "a body with no trailing newline" "no trailing newline" "$(cat "$work/body")"

# An empty body does not invoke `mail` at all.  This is the whole point of the
# script:  an empty message from a cron job should be silent, and `mail` should
# not even get a chance to complain about its arguments.
rm -f "$work/args" "$work/body"
actual_status=0
printf '' | "$MAIL_E" -invalidoption || actual_status=$?
check_equal "an empty body exits 0" "0" "$actual_status"
if [ -e "$work/args" ]; then
  echo "FAIL: an empty body should not invoke mail, but it was invoked with:"
  cat "$work/args"
  status=1
else
  echo "PASS: an empty body does not invoke mail"
fi

# `mail`'s exit status is propagated when `mail` is invoked.
echo 7 > "$work/mail-exit-status"
actual_status=0
printf 'the body\n' | "$MAIL_E" someone@example.com || actual_status=$?
check_equal "mail's exit status is propagated" "7" "$actual_status"

# ... but a failing `mail` is irrelevant when there is nothing to send.
actual_status=0
printf '' | "$MAIL_E" someone@example.com || actual_status=$?
check_equal "an empty body ignores a failing mail" "0" "$actual_status"
echo 0 > "$work/mail-exit-status"

# The temporary file holding the body is created under $TMPDIR when that is
# set, and is removed afterward.  Checking only that $TMPDIR is empty at the
# end would also pass if `mail-e` stopped honoring $TMPDIR and put its
# temporary file in /tmp, so check that the file was there while `mail-e` ran.
mkdir "$work/tmpdir"
rm -f "$work/tmpdir-during"
printf 'the body\n' | TMPDIR="$work/tmpdir" "$MAIL_E" someone@example.com
case "$(cat "$work/tmpdir-during")" in
  maile-input.*)
    echo "PASS: the temporary file is created under \$TMPDIR"
    ;;
  *)
    echo "FAIL: the temporary file is not created under \$TMPDIR;"
    echo "  \$TMPDIR held: <<$(cat "$work/tmpdir-during")>>"
    status=1
    ;;
esac
leftover="$(find "$work/tmpdir" -mindepth 1)"
check_equal "the temporary file is removed" "" "$leftover"

exit "$status"
