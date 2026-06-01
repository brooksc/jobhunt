#!/bin/sh
set -u

stopping=0
child_pid=""

stop_loop() {
  stopping=1
  if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
}

trap stop_loop INT TERM

while [ "$stopping" -eq 0 ]; do
	npm test 
	npm run typecheck 
	npm run lint 
  node server/index.js serve "$@" &
  child_pid=$!
  wait "$child_pid"
  code=$?
  child_pid=""

  if [ "$stopping" -ne 0 ]; then
    exit 0
  fi

  printf '[jobhunt] server exited with code %s; restarting in 1s...\n' "$code" >&2
  sleep 1
done
