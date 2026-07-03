#!/bin/sh

BB="/opt/busybox-mips"

SELF_PID="$$"
PARENT_PID="$PPID"

echo "Scanning /dev/pty* ..."

for dev in /dev/pty*; do
  [ -e "$dev" ] || continue

  PIDS="$("$BB" fuser "$dev" 2>/dev/null)"

  [ -n "$PIDS" ] || continue

  echo "$dev: $PIDS"

  for pid in $PIDS; do
    case "$pid" in
      ''|*[!0-9]*)
        continue
        ;;
    esac

    if [ "$pid" = "$SELF_PID" ] || [ "$pid" = "$PARENT_PID" ]; then
      echo "skip pid $pid"
      continue
    fi

    echo "kill pid $pid using $dev"
    kill "$pid" 2>/dev/null
  done
done

echo "Done."
