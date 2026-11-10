#!/usr/bin/env python3
"""Archive discoverable public files from play.samp.directory locally.

This intentionally does not log in, request private endpoints, or put any
downloaded file in Git. It records missing URLs instead of claiming a full
server-side copy.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit, unquote
from urllib.request import Request, urlopen
import hashlib
import json
import os
import re
import sys

BASE = "https://play.samp.directory/"
SOLO_URL = "https://samp.directory/tools/world"
PAGES = ("/", "/ru", "/es", "/pt", "/tr", "/offline")
ROOT = Path(__file__).resolve().parent / "local-only"
SITE = ROOT / "site"
MANIFEST = ROOT / "manifest.json"
USER_AGENT = "ZGTA-SA-local-preservation/1.0"
ALLOWED_PREFIXES = ("/_next/static/", "/game/", "/reference/", "/tools/map/")
EXTRA = ("/manifest.webmanifest", "/favicon.ico", "/icon.png", "/apple-icon.png", "/sw.js", "/icons/icon-192.png")
GAME_SEEDS = (
    "/game/world/index.json", "/game/world/collision.json",
    "/game/world/peds.json", "/game/world/fx.json",
    "/game/world/pedanims.bin", "/game/particle.txd",
    "/game/effectspc.txd", "/game/maccer.dff", "/game/maccer.txd",
    "/game/desert_eagle.dff", "/game/desert_eagle.txd",
    "/game/diamond_3.dff", "/tools/map/lights.json",
    "/tools/map/lights.bin", "/reference/hud/font1.png",
    "/reference/hud/font2.png",
)
PATH_RE = re.compile(r"(?:https://play\.samp\.directory)?(/(?:_next/static|game|reference|tools/map)/[A-Za-z0-9_./?=&%+:-]+)")


class Assets(HTMLParser):
    def __init__(self, base=BASE):
        super().__init__()
        self.base = base
        self.urls = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for key in ("src", "href", "poster"):
            if attrs.get(key):
                self.urls.add(urljoin(self.base, attrs[key]))


def normalize(url):
    parsed = urlsplit(urljoin(BASE, url))
    if parsed.netloc == "samp.directory" and parsed.path == "/tools/world":
        return SOLO_URL
    if parsed.netloc not in ("play.samp.directory", "samp.directory"):
        return None
    path = unquote(parsed.path)
    if path in PAGES:
        return BASE.rstrip("/") + path
    if path.endswith("/"):
        return None
    if path.startswith(ALLOWED_PREFIXES) or path in EXTRA:
        return BASE.rstrip("/") + path
    return None


def local_path(url):
    path = urlsplit(url).path
    if path in PAGES or path == "/tools/world":
        path = (path.rstrip("/") or "") + "/index.html"
    target = (SITE / path.lstrip("/")).resolve()
    if target != SITE.resolve() and SITE.resolve() not in target.parents:
        raise ValueError("Unsafe path: " + url)
    return target


def fetch(url):
    target = local_path(url)
    if target.is_file() and target.stat().st_size:
        data = target.read_bytes()
        return url, {"path": str(target.relative_to(ROOT)), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "status": "ok"}, data
    req = Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urlopen(req, timeout=90) as response:
            data = response.read()
            content_type = response.headers.get("Content-Type", "")
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".partial")
        tmp.write_bytes(data)
        os.replace(tmp, target)
        return url, {"path": str(target.relative_to(ROOT)), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "content_type": content_type, "status": "ok"}, data
    except Exception as exc:
        return url, {"status": "error", "error": str(exc)}, b""


def discover(url, data):
    found = set()
    path = urlsplit(url).path
    if path in PAGES or url == SOLO_URL:
        parser = Assets(url)
        parser.feed(data.decode("utf-8", "replace"))
        found |= parser.urls
        if path in PAGES:
            found |= {urljoin(BASE, p) for p in EXTRA}
            found |= {urljoin(BASE, p) for p in GAME_SEEDS}
            found |= {urljoin(BASE, p) for p in PAGES}
            found.add(SOLO_URL)
    if path.endswith((".js", ".json", ".css", ".webmanifest")):
        body = data.decode("utf-8", "replace")
        found |= {urljoin(BASE, p) for p in PATH_RE.findall(body)}
        if path.startswith("/_next/static/chunks/webpack-"):
            found |= {urljoin(BASE, "/_next/" + p) for p in re.findall(r'"(static/chunks/[A-Za-z0-9_.-]+\.js)"', body)}
            mapping = body.split('a.u=e=>', 1)[-1].split(',a.miniCssF=', 1)[0]
            for number, digest in re.findall(r'(\d+):"([a-f0-9]{16})"', mapping):
                stem = {"907": "3638d954", "6079": "363642f4"}.get(number, number)
                found.add(urljoin(BASE, "/_next/static/chunks/%s.%s.js" % (stem, digest)))
        if path.endswith(".css"):
            found |= {urljoin(url, x) for x in re.findall(r"url\(['\"]?([^)'\"]+)", body)}
    if path == "/game/world/index.json":
        try:
            index = json.loads(data)
            for tile in index.get("tiles", []):
                found.add(urljoin(BASE, "/game/world/" + tile["name"] + ".bin"))
            for section in ("detail", "inside"):
                for cell in index.get(section, {}).get("cells", []):
                    n = cell["cell"]
                    for extension in ("bin", "col.bin", "brk.bin"):
                        found.add(urljoin(BASE, "/game/world/c%d.%s" % (n, extension)))
        except (ValueError, KeyError, TypeError):
            pass
    if path == "/game/world/peds.json":
        try:
            for ped in json.loads(data).get("peds", []):
                if not isinstance(ped, list) or len(ped) < 2:
                    continue
                for name, extension in ((ped[0], "dff"), (ped[1], "txd")):
                    if isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_-]+", name) and name.lower() != "null":
                        found.add(urljoin(BASE, "/game/%s.%s" % (name.lower(), extension)))
        except (ValueError, TypeError):
            pass
    return {item for x in found if (item := normalize(x))}


def save(rows):
    ROOT.mkdir(parents=True, exist_ok=True)
    tmp = MANIFEST.with_suffix(".json.partial")
    tmp.write_text(json.dumps({"source": BASE, "captured_at": datetime.now(timezone.utc).isoformat(), "files": rows}, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, MANIFEST)


def main():
    rows = {}
    if MANIFEST.exists():
        rows = json.loads(MANIFEST.read_text()).get("files", {})
    pending = {BASE, SOLO_URL}
    processed = set()
    while pending:
        batch = sorted(pending - processed)
        pending.clear()
        if not batch:
            break
        print("Fetching", len(batch), "files; completed", len(processed), flush=True)
        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = [pool.submit(fetch, url) for url in batch]
            for future in as_completed(futures):
                url, row, data = future.result()
                rows[url] = row
                processed.add(url)
                if row["status"] == "ok":
                    pending |= discover(url, data) - processed
                else:
                    print("Missing:", url, row["error"], file=sys.stderr, flush=True)
        save(rows)
    ok = [row for row in rows.values() if row["status"] == "ok"]
    print("Archived", len(ok), "files,", sum(row["bytes"] for row in ok), "bytes; errors", len(rows) - len(ok))


if __name__ == "__main__":
    main()
