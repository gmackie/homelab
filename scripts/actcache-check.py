#!/usr/bin/env python3
"""Check a Forgejo runner Actions cache server against a secret file (FORGE-463).

Does what actions/cache does through the runner's cache proxy: reserve, upload,
commit, look up and download one small entry, with request MACs computed from
the secret (forgejo runner act/artifactcache/mac.go). Prints only "ok",
"rejected" or an error; never the secret or a MAC.

  actcache-check.py --url http://100.121.231.92:8090 \
      --secret-file /etc/forgejo-runner/cache-secret --expect ok
  actcache-check.py --url ... --secret-file /root/old-secret --expect rejected

Exit status 0 when the result matches --expect.
"""

import argparse
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "/_apis/artifactcache"
REPO = "ops/actcache-check"


def compute_mac(secret, repo, run, ts, write_isolation_key):
    mac = hmac.new(secret.encode(), digestmod=hashlib.sha256)
    mac.update(f"{repo}>{run}>{ts}>{write_isolation_key}".encode())
    return mac.hexdigest()


def _read_secret(path):
    with open(path, encoding="utf-8") as f:
        return f.read().strip()


class Rejected(Exception):
    pass


def check(url, secret_file, timeout=15):
    """Return "ok" for a full round trip, "rejected" when the server answers 403."""
    secret = _read_secret(secret_file)
    url = url.rstrip("/")
    run = str(int(time.time()))
    ts = str(int(time.time()) - 1)
    headers = {
        "Forgejo-Cache-Repo": REPO,
        "Forgejo-Cache-RunNumber": run,
        "Forgejo-Cache-Timestamp": ts,
        "Forgejo-Cache-WriteIsolationKey": "",
        "Forgejo-Cache-Host": url,
        "Forgejo-Cache-RunId": "0",
        "Forgejo-Cache-MAC": compute_mac(secret, REPO, run, ts, ""),
    }
    del secret

    def call(method, path, body=None, extra=None, raw=False):
        h = dict(headers, **(extra or {}))
        data = None
        if body is not None:
            data = body if isinstance(body, bytes) else json.dumps(body).encode()
            h.setdefault("Content-Type", "application/json")
        req = urllib.request.Request(url + path, data=data, method=method, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                payload = resp.read()
                return resp.status, payload if raw else (json.loads(payload) if payload else None)
        except urllib.error.HTTPError as e:
            if e.code == 403:
                raise Rejected() from None
            raise RuntimeError(f"{method} {path}: HTTP {e.code}") from None

    key = f"actcache-check-{run}-{os.urandom(6).hex()}"
    version = hashlib.sha256(key.encode()).hexdigest()
    blob = os.urandom(256)
    try:
        status, found = call("GET", f"{BASE}/cache?keys={key}&version={version}")
        if status != 204:
            raise RuntimeError(f"fresh key unexpectedly found (HTTP {status})")
        _, reserved = call("POST", f"{BASE}/caches", {"key": key, "version": version, "cacheSize": len(blob)})
        cid = reserved["cacheId"]
        call("PATCH", f"{BASE}/caches/{cid}", blob,
             {"Content-Type": "application/octet-stream", "Content-Range": f"bytes 0-{len(blob) - 1}/*"})
        call("POST", f"{BASE}/caches/{cid}", {"size": len(blob)})
        status, found = call("GET", f"{BASE}/cache?keys={key}&version={version}")
        if status != 200 or found.get("result") != "hit":
            raise RuntimeError(f"committed entry not found (HTTP {status})")
        loc = found["archiveLocation"]
        art = loc[loc.index(BASE):] if BASE in loc else loc
        _, data = call("GET", art, raw=True)
        if data != blob:
            raise RuntimeError("downloaded entry differs from upload")
    except Rejected:
        return "rejected"
    return "ok"


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--url", required=True)
    p.add_argument("--secret-file", required=True)
    p.add_argument("--expect", choices=["ok", "rejected"], required=True)
    a = p.parse_args(argv)
    try:
        result = check(a.url, a.secret_file)
    except Exception as e:  # message carries no secret material
        print(f"error: {e}")
        return 2
    print(result)
    return 0 if result == a.expect else 1


if __name__ == "__main__":
    sys.exit(main())
