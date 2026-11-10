#!/bin/zsh
# Run the archived client with an independent server on this Mac.
set -euo pipefail

project_dir="${0:A:h}"
local_dir="$project_dir/local-only"
port="${ZGTA_LOCAL_PORT:-8766}"

if [[ ! -f "$local_dir/site/index.html" || ! -f "$local_dir/manifest.json" ]]; then
  print -u2 'Local archive missing. Run python3 archive_site.py first.'
  exit 1
fi
if ! [[ "$port" =~ '^[0-9]{1,5}$' ]] || (( port < 1024 || port > 65535 )); then
  print -u2 'ZGTA_LOCAL_PORT must be between 1024 and 65535.'
  exit 1
fi

ready() {
  local response
  response="$(curl --noproxy '*' --fail --silent --show-error \
    "http://127.0.0.1:$port/api/local/status" 2>/dev/null)" || return 1
  [[ "$response" == *'"selfhost":true'* ]]
}

server_pid=''
if ! ready; then
  ZGTA_SELFHOST=1 PORT="$port" node "$project_dir/serve_local.js" \
    > "$local_dir/selfhost-server.log" 2>&1 &
  server_pid=$!
  trap 'kill "$server_pid" 2>/dev/null || true' EXIT
  connected=0
  for attempt in {1..40}; do
    if ready; then connected=1; break; fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat "$local_dir/selfhost-server.log" >&2
      exit 1
    fi
    sleep 0.25
  done
  if (( ! connected )); then
    print -u2 "The self-hosted server did not start. Port $port may be in use."
    exit 1
  fi
fi

print "Opening ZGTA:SA local multiplayer at http://127.0.0.1:$port/"
open -a '/Applications/Google Chrome.app' "http://127.0.0.1:$port/"
if [[ -n "$server_pid" ]]; then
  print 'Keep this Terminal window open while playing. Press Ctrl-C here to stop the local server.'
  wait "$server_pid"
fi
