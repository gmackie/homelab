"""FORGE-463: the hetzner-fg Actions cache secret stays out of argv and the
verifier talks the cache server's MAC protocol (forgejo runner v13
act/artifactcache/mac.go)."""

import hashlib
import hmac
import importlib.util
import json
import pathlib
import re
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
FG = ROOT / "ops" / "hetzner-fg"

spec = importlib.util.spec_from_file_location("actcache_check", ROOT / "scripts" / "actcache-check.py")
actcache_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(actcache_check)


class UnitAndConfig(unittest.TestCase):
    def test_unit_reads_config_and_never_passes_secret(self):
        unit = (FG / "forgejo-cache-server.service").read_text()
        exec_lines = [l for l in unit.splitlines() if l.startswith("ExecStart=")]
        self.assertEqual(len(exec_lines), 1)
        self.assertNotIn("--secret", exec_lines[0])
        self.assertNotRegex(exec_lines[0], r"(^|\s)-s(\s|$)")
        self.assertIn("-c /etc/forgejo-runner/cache-server.yaml", exec_lines[0])
        self.assertNotRegex(unit, r"(?im)^Environment=.*secret")

    def test_config_uses_secret_url_only(self):
        cfg = (FG / "cache-server.yaml").read_text()
        self.assertIn('secret_url: "file:/etc/forgejo-runner/cache-secret"', cfg)
        self.assertNotRegex(cfg, r"(?m)^\s*secret\s*:")
        self.assertRegex(cfg, r"(?m)^\s*port:\s*8090$")


SECRET = "s3cr3t-for-tests"


def go_mac(secret, repo, run, ts, key):
    m = hmac.new(secret.encode(), digestmod=hashlib.sha256)
    for i, part in enumerate((repo, run, ts, key)):
        if i:
            m.update(b">")
        m.update(part.encode())
    return m.hexdigest()


class FakeCache(BaseHTTPRequestHandler):
    store = {}
    caches = {}

    def log_message(self, *a):
        pass

    def _ok(self):
        h = self.headers
        mac = go_mac(SECRET, h["Forgejo-Cache-Repo"], h["Forgejo-Cache-RunNumber"],
                     h["Forgejo-Cache-Timestamp"], h.get("Forgejo-Cache-WriteIsolationKey", ""))
        if not hmac.compare_digest(mac, h.get("Forgejo-Cache-MAC", "")):
            self._json(403, {"error": "validation error"})
            return False
        return True

    def _json(self, code, body=None):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(code)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", 0)))

    def do_POST(self):
        if not self._ok():
            return
        if self.path.endswith("/caches"):
            req = json.loads(self._body())
            cid = len(self.caches) + 1
            self.caches[cid] = {"key": req["key"], "version": req["version"], "done": False}
            self._json(200, {"cacheId": cid})
        else:
            cid = int(self.path.rsplit("/", 1)[1])
            self._body()
            self.caches[cid]["done"] = True
            self._json(200)

    def do_PATCH(self):
        if not self._ok():
            return
        cid = int(self.path.rsplit("/", 1)[1])
        self.store[cid] = self._body()
        self._json(200)

    def do_GET(self):
        if not self._ok():
            return
        if "/artifacts/" in self.path:
            cid = int(self.path.rsplit("/", 1)[1])
            data = self.store[cid]
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        for cid, c in self.caches.items():
            if c["done"] and c["key"] in self.path:
                self._json(200, {"result": "hit", "archiveLocation": f"{self.headers['Forgejo-Cache-Host']}/x/_apis/artifactcache/artifacts/{cid}"})
                return
        self._json(204)


class Verifier(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), FakeCache)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.srv.server_address[1]}"
        cls.tmp = tempfile.TemporaryDirectory()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.tmp.cleanup()

    def secret_file(self, value):
        p = pathlib.Path(self.tmp.name) / f"s{abs(hash(value))}"
        p.write_text(value + "\n")
        return str(p)

    def test_mac_matches_runner_algorithm(self):
        self.assertEqual(actcache_check.compute_mac("k", "o/r", "7", "100", "w"),
                         go_mac("k", "o/r", "7", "100", "w"))

    def test_round_trip_with_correct_secret(self):
        result = actcache_check.check(self.url, self.secret_file(SECRET))
        self.assertEqual(result, "ok")

    def test_wrong_secret_rejected(self):
        result = actcache_check.check(self.url, self.secret_file("old-secret"))
        self.assertEqual(result, "rejected")

    def test_output_never_contains_secret(self):
        import contextlib
        import io
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            actcache_check.main(["--url", self.url, "--secret-file", self.secret_file(SECRET), "--expect", "ok"])
            actcache_check.main(["--url", self.url, "--secret-file", self.secret_file("old-secret"), "--expect", "rejected"])
        self.assertNotIn(SECRET, buf.getvalue())
        self.assertNotIn("old-secret", buf.getvalue())
        self.assertFalse(re.search(r"[0-9a-f]{64}", buf.getvalue()))


if __name__ == "__main__":
    unittest.main()
