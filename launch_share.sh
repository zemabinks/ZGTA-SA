#!/bin/zsh
# Share one self-hosted game instance over LAN, Tailscale, or both.
set -euo pipefail

project_dir="${0:A:h}"
local_dir="$project_dir/local-only"
mode="${1:-lan}"
port="${ZGTA_LOCAL_PORT:-8766}"
join_file="$local_dir/selfhost/join-code.txt"

if [[ "$mode" != lan && "$mode" != tailnet && "$mode" != both ]]; then
  print -u2 'Use: zsh launch_share.sh [lan|tailnet|both]'
  exit 1
fi
if ! [[ "$port" =~ '^[0-9]{1,5}$' ]] || (( port < 1024 || port > 65535 )); then
  print -u2 'ZGTA_LOCAL_PORT must be between 1024 and 65535.'
  exit 1
fi
if [[ ! -f "$local_dir/site/index.html" || ! -f "$local_dir/manifest.json" ]]; then
  print -u2 'Local archive missing. Run python3 tools/archive/archive_site.py first.'
  exit 1
fi
zsh "$project_dir/prepare_native_runtime.sh"

mkdir -p "$local_dir/selfhost"
if [[ ! -f "$join_file" ]]; then
  umask 077
  openssl rand -hex 24 > "$join_file"
fi
chmod 600 "$join_file"

lan_ip=''
tailnet_host=''
allowed_hosts=''
bind_host='127.0.0.1'
if [[ "$mode" == lan || "$mode" == both ]]; then
  lan_ip="${ZGTA_LAN_IP:-$(ipconfig getifaddr en0 2>/dev/null || ifconfig en0 2>/dev/null | awk '/^[[:space:]]*inet / {print $2; exit}')}"
  if [[ -z "$lan_ip" ]]; then
    print -u2 'No LAN address found. Set ZGTA_LAN_IP to this Mac’s home-network IPv4 address.'
    exit 1
  fi
  allowed_hosts="$lan_ip:$port"
  bind_host='0.0.0.0'
fi
if [[ "$mode" == tailnet || "$mode" == both ]]; then
  if ! command -v tailscale >/dev/null; then
    print -u2 'Tailscale CLI is required for private internet sharing.'
    exit 1
  fi
  tailnet_host="$(tailscale status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d.get("Self") or {}; print((s.get("DNSName") or "").rstrip(".") if d.get("BackendState")=="Running" and s.get("Online") else "")')"
  if [[ -z "$tailnet_host" ]]; then
    print -u2 'Tailscale is not connected.'
    exit 1
  fi
  allowed_hosts="${allowed_hosts:+$allowed_hosts,}$tailnet_host:8443"
fi

route_state='none'
if [[ -n "$tailnet_host" ]]; then
  route_state="$(tailscale serve status --json | python3 -c '
import json,sys
d=json.load(sys.stdin)
target="http://127.0.0.1:"+sys.argv[1]
web=d.get("Web") or {}
matches=[v for k,v in web.items() if k.endswith(":8443")]
if matches:
    print("same" if len(matches)==1 and ((matches[0].get("Handlers") or {}).get("/") or {}).get("Proxy")==target else "other")
else:
    print("other" if "8443" in (d.get("TCP") or {}) else "none")
' "$port")"
  if [[ "$route_state" == other ]]; then
    print -u2 'Tailscale port 8443 already serves another app. Nothing was changed.'
    exit 1
  fi
fi

ready() {
  local response
  response="$(curl --noproxy '*' --fail --silent --show-error \
    "http://127.0.0.1:$port/api/local/status" 2>/dev/null)" || return 1
  python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
    expected=[h for h in sys.argv[2].split(",") if h]
    ok=(data.get("selfhost") is True and data.get("joinCodeRequired") is True
        and data.get("lanAccessible") is (sys.argv[1]=="0.0.0.0")
        and data.get("allowedHosts")==expected)
    sys.exit(0 if ok else 1)
except (ValueError, TypeError):
    sys.exit(1)
' "$bind_host" "$allowed_hosts" <<< "$response"
}

if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  print -u2 "Port $port is in use. Stop the existing local game server, then rerun this launcher."
  exit 1
fi
BIND_HOST="$bind_host" ZGTA_SELFHOST=1 PORT="$port" \
  ZGTA_JOIN_CODE_FILE="$join_file" ZGTA_ALLOWED_HOSTS="$allowed_hosts" \
  node "$project_dir/serve_local.js" > "$local_dir/selfhost-server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
started=0
for attempt in {1..40}; do
  if ready; then started=1; break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$local_dir/selfhost-server.log" >&2
    exit 1
  fi
  sleep 0.25
done
if (( ! started )); then
  print -u2 'The shared local server did not start.'
  exit 1
fi

if [[ -n "$tailnet_host" ]]; then
  if [[ "$route_state" == same ]]; then
    print 'Existing private Tailscale HTTPS route matches this game server.'
  elif ! tailscale serve --bg --https=8443 "http://127.0.0.1:$port"; then
    print -u2 'Tailscale Serve could not start. LAN access, if selected, remains available.'
  else
    route_state='same'
  fi
  if [[ "$route_state" == same ]]; then
    print "Private internet URL: https://$tailnet_host:8443/"
  fi
fi
if [[ -n "$lan_ip" ]]; then
  print "LAN URL: http://$lan_ip:$port/"
fi
print "Join code is stored only on this Mac: $join_file"
print 'Share the URL and code only with people you want to invite.'
if [[ "${ZGTA_NO_OPEN:-0}" != 1 ]]; then
  open -a '/Applications/Google Chrome.app' "http://127.0.0.1:$port/"
fi
print 'Keep this Terminal window open while hosting. Press Ctrl-C to stop the local game server.'
wait "$server_pid"
