#!/bin/zsh
# Run the local mirror at the game's real HTTPS origin in a separate Chrome profile.
set -euo pipefail

project_dir="${0:A:h}"
local_dir="$project_dir/local-only"
chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cert_path="$local_dir/connected.crt"
key_path="$local_dir/connected.key"
profile_dir="$local_dir/connected-chrome-profile"

if [[ ! -f "$local_dir/site/index.html" || ! -f "$local_dir/manifest.json" ]]; then
  print -u2 'Local archive missing. Run python3 archive_site.py first.'
  exit 1
fi
if [[ ! -x "$chrome_bin" ]]; then
  print -u2 'Google Chrome was not found in /Applications.'
  exit 1
fi

mkdir -p "$local_dir" "$profile_dir"
if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout "$key_path" -out "$cert_path" \
    -subj '/CN=play.samp.directory' \
    -addext 'subjectAltName=DNS:play.samp.directory' >/dev/null 2>&1
  chmod 600 "$key_path"
fi

spki_hash="$(openssl x509 -in "$cert_path" -pubkey -noout | \
  openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64 -A)"

PORT=9443 ZGTA_CONNECTED=1 node "$project_dir/serve_local.js" \
  > "$local_dir/connected-server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

ready=0
for attempt in {1..40}; do
  if curl --noproxy '*' --silent --show-error --output /dev/null \
      --connect-to play.samp.directory:443:127.0.0.1:9443 \
      --cacert "$cert_path" 'https://play.samp.directory/' 2>/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$local_dir/connected-server.log" >&2
    exit 1
  fi
  sleep 0.25
done
if [[ "$ready" -ne 1 ]]; then
  cat "$local_dir/connected-server.log" >&2
  print -u2 'Connected mirror did not start.'
  exit 1
fi

print 'Opening the ZGTA:SA connected window. Sign in there with Discord.'
"$chrome_bin" \
  --user-data-dir="$profile_dir" \
  --no-first-run --no-default-browser-check --no-proxy-server --disable-quic \
  '--host-resolver-rules=MAP play.samp.directory 127.0.0.1:9443' \
  --ignore-certificate-errors-spki-list="$spki_hash" \
  'https://play.samp.directory/'
