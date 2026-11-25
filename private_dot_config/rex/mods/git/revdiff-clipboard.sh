#!/bin/sh

output=$(mktemp "${TMPDIR:-/tmp}/rex-revdiff.XXXXXX") || exit 1
trap 'rm -f "$output"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/opt/homebrew/bin/revdiff --output "$output" "$@"
review_status=$?

case "$review_status" in
  0|10)
    if [ -s "$output" ]; then
      cat "$output"
      /usr/bin/pbcopy < "$output" || exit 1
    fi
    ;;
esac

exit "$review_status"
