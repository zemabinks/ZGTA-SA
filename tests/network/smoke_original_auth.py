#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compile the real native authentication owner; exercise an owned loopback API.

No production account, service request, credential, or browser cookie is used.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib
import json
from pathlib import Path
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "local-only/research/original-auth-helper"
OUT.mkdir(parents=True, exist_ok=True)
events = []
event_lock = threading.Lock()
counts = {}


class Fixture(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            # The client must close oversized/cancelled responses early.
            pass

    def log_message(self, *_):
        pass

    def do_GET(self):
        self.handle_owned()

    def do_POST(self):
        self.handle_owned()

    def reply(self, value, status=200, mime="application/json", headers=None):
        payload = json.dumps(value, ensure_ascii=False).encode() if not isinstance(value, bytes) else value
        try:
            self.send_response(status)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(payload)))
            for name, value in (headers or {}).items():
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def handle_owned(self):
        scenario = self.headers.get("X-ZGTA-Test", "")
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        with event_lock:
            index = counts.get((scenario, self.path), 0) + 1
            counts[(scenario, self.path)] = index
            events.append(dict(scenario=scenario, method=self.command, path=self.path,
                               body=body.decode(), accept=self.headers.get("Accept"),
                               content_type=self.headers.get("Content-Type"),
                               cookie=self.headers.get("Cookie", "")))
        if self.path == "/__health":
            return self.reply({"healthy": True})
        if scenario in ("cancelled", "released") or scenario == "superseded" and index == 1:
            time.sleep(0.4)
        if scenario.startswith("http-"):
            return self.reply({"error": "owned failure"}, int(scenario[5:]))
        if scenario.startswith("redirect-"):
            # Reject before following or resubmitting, even on the same origin.
            return self.reply({}, 307, headers={"Location": "/__must_not_follow"})
        if scenario == "length-limit":
            return self.reply(b"x" * 65537)
        if scenario == "chunk-limit":
            try:
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                for _ in range(80):
                    chunk = b"x" * 4096
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                    self.wfile.flush()
                    time.sleep(0.001)
                self.wfile.write(b"0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if self.path == "/api/auth/guest":
            if scenario.startswith("blocked-"):
                code = scenario[8:]
                return self.reply({"error": code, "message": "Fixture says " + code}, 403)
            if scenario == "logical-reject":
                return self.reply({"ok": False, "error": "lookalike", "message": "Pick another name"})
            if scenario == "sanitized-message":
                return self.reply({"error": "many\x00", "message": "Please\n wait\x00"}, 429)
            return self.reply({"ok": True}, headers={"Set-Cookie": "owned_fixture_session=synthetic; Path=/; HttpOnly; SameSite=Lax"})
        if self.path == "/game/build":
            value = {"bad-build-short": "20261116150", "bad-build-ascii": "20261116150😀", "bad-build-number": 202611161501}.get(scenario, "202611161501")
            return self.reply({"build": value})
        value = {"available": True, "guests": True, "loggedIn": True, "guest": False, "username": "Fixture Account"}
        if scenario in ("guest-success", "guest-boundary"):
            if "owned_fixture_session=synthetic" not in self.headers.get("Cookie", ""):
                return self.reply({"loggedIn": False})
            value.update(guest=True, username="QA Guest")
        elif scenario == "account-public":
            value = {"available": True, "guests": True, "loggedIn": False}
        elif scenario in ("anonymous", "verify-denied"):
            value = {"loggedIn": False}
        elif scenario == "account-fallback":
            value = {"loggedIn": True, "discordName": "Legacy Account"}
        elif scenario == "account-optional":
            value = {"loggedIn": True}
        elif scenario.startswith("bad-field-"):
            field = scenario[10:]
            value[field] = 1 if field not in ("username", "discordName") else ["not a string"]
        elif scenario == "array":
            value = []
        elif scenario == "invalid-json":
            return self.reply(b"{bad json")
        elif scenario == "wrong-mime":
            return self.reply(value, mime="text/html")
        elif scenario == "oversize-name":
            value["username"] = "a" * 257
        elif scenario == "superseded":
            value["username"] = "Stale generation" if index == 1 else "Current generation"
        return self.reply(value)


server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
compile_cmd = ["xcrun", "swiftc", "-swift-version", "5", "-module-cache-path", str(OUT / "modules"),
               str(ROOT / "ios/App/NativeOriginalWorldAuthentication.swift"),
               str(ROOT / "tests/original_auth/main.swift"), "-o", str(OUT / "original-auth-tests")]
try:
    build = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=120)
    (OUT / "compile.log").write_text(build.stdout + build.stderr)
    if build.returncode:
        raise SystemExit(build.stdout + build.stderr)
    run = subprocess.run([str(OUT / "original-auth-tests"), f"http://127.0.0.1:{server.server_port}/"],
                         capture_output=True, text=True, timeout=65)
    (OUT / "test.log").write_text(run.stdout + run.stderr)
    if run.returncode:
        raise SystemExit(run.stdout + run.stderr)
    result = json.loads(run.stdout.strip().splitlines()[-1])
    fixture_checks = 0
    def fixture_check(condition, message):
        global fixture_checks
        fixture_checks += 1
        if not condition:
            raise AssertionError(message)
    fixture_check(result["passed"], "native regression reports success")
    def subset(scenario):
        return [event for event in events if event["scenario"] == scenario]
    for scenario in ("guest-success", "guest-boundary"):
        rows = subset(scenario)
        fixture_check([row["path"] for row in rows[:3]] == ["/api/auth/guest", "/api/auth/me", "/game/build"], "ordered verify/build")
        fixture_check(sum(row["method"] == "POST" for row in rows) == 1, "one explicit POST")
        fixture_check(rows[0]["accept"] == rows[0]["content_type"] == "application/json", "actual JSON headers")
        fixture_check(json.loads(rows[0]["body"]) == {"name": "QA Guest" if scenario == "guest-success" else "😀" * 12}, "exact trimmed name body")
        fixture_check(all("owned_fixture_session=synthetic" in row["cookie"] for row in rows[1:]), "same owner cookie continuity")
    for code in ("closed", "vpn", "lookalike", "many"):
        fixture_check(len(subset("blocked-" + code)) == 1, "blocked Guest POST must not retry/bootstrap")
    fixture_check(len(subset("logical-reject")) == 1, "logical rejection has no bootstrap")
    fixture_check([row["path"] for row in subset("verify-denied")] == ["/api/auth/guest", "/api/auth/me"], "failed account verification has no build")
    fixture_check(all(not row["scenario"].startswith("invalid-name-") for row in events), "invalid name never requests network")
    fixture_check(all(row["path"] != "/__must_not_follow" for row in events), "redirect never followed")
    fixture_check(all(row["path"] != "/game/build" for row in subset("anonymous")), "unsigned account never requests build")
    result.update(fixtureAssertions=fixture_checks, fixture="independent owned HTTP server bound to 127.0.0.1 only",
                  productionRequests=0, sourceHashes={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in [ROOT / "ios/App/NativeOriginalWorldAuthentication.swift", ROOT / "tests/original_auth/main.swift", ROOT / "tests/network/smoke_original_auth.py"]})
    (OUT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, sort_keys=True))
finally:
    server.shutdown()
    server.server_close()
