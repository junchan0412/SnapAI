#!/usr/bin/env python3
import collections
import datetime
import hashlib
import http.server
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import threading
import time
import urllib.parse
import zlib
from zoneinfo import ZoneInfo

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
REQUESTS = []
LOCK = threading.Lock()


def png_chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


PNG = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 32, 32, 8, 6, 0, 0, 0))
PNG += png_chunk(b"IDAT", zlib.compress((b"\x00" + bytes([50, 160, 120, 255]) * 32) * 32))
PNG += png_chunk(b"IEND", b"")
ICO = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", 32, 32, 0, 0, 1, 32, len(PNG), 22) + PNG


class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        with LOCK:
            REQUESTS.append({"method": "GET", "path": path,
                             "authorization_present": "Authorization" in self.headers,
                             "cookie_present": "Cookie" in self.headers})
        status, content_type, payload, headers = 200, "text/html", b"", {}
        if path == "/relative/":
            payload = b"<html><head><link REL='shortcut icon' HREF='assets/icon.png'></head></html>"
            headers["Set-Cookie"] = "fixture=1; Path=/"
        elif path == "/relative/assets/icon.png":
            content_type, payload = "image/png", PNG
        elif path == "/redirect/":
            status, headers["Location"] = 302, "/redirected/page/"
        elif path == "/redirected/page/":
            payload = b'<link href="../assets/icon.png" rel="apple-touch-icon">'
            headers["Set-Cookie"] = "fixture=1; Path=/"
        elif path == "/redirected/assets/icon.png":
            status, headers["Location"] = 302, "/images/redirect.png"
        elif path == "/images/redirect.png":
            content_type, payload = "image/png", PNG
        elif path == "/fallback/":
            payload = "".join(f'<link rel="icon" href="broken-{i}.png">' for i in range(9)).encode()
        elif path == "/fallback/favicon.ico":
            content_type, payload = "image/x-icon", ICO
        elif path == "/concurrent/":
            time.sleep(0.15)
            payload = b'<link href="icon.png" rel="icon">'
        elif path == "/concurrent/icon.png":
            time.sleep(0.15)
            content_type, payload = "image/png", PNG
        else:
            status = 404
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    products = REPO / ".build/debug"
    module = products / "SnapAILogic.swiftmodule/arm64-apple-macos.swiftmodule"
    logic_object = products / "SnapAILogic.o"
    implementation = REPO / "Sources/SnapAI/ProviderIconView.swift"
    probe_source = HERE / "provider-icon-probe.swift"
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    metadata = {"timestamp": datetime.datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
                "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
                "module_sha256": digest(module), "logic_object_sha256": digest(logic_object),
                "implementation_sha256": digest(implementation), "probe_sha256": digest(probe_source),
                "build_products": str(products.resolve()), "fixture": "localhost HTTP only"}
    env = dict(os.environ)
    env.pop("SNAPAI_LOGIC_TESTS", None)
    try:
        with tempfile.TemporaryDirectory(prefix="snapai-provider-icon-probe-") as temporary:
            temp = pathlib.Path(temporary)
            executable = temp / "ProviderIconProbe"
            command = ["xcrun", "swiftc", "-parse-as-library", "-package-name", "snapai", "-I", str(products),
                       str(implementation), str(probe_source), str(logic_object), "-o", str(executable),
                       "-framework", "AppKit", "-framework", "SwiftUI", "-framework", "Carbon",
                       "-framework", "ApplicationServices", "-framework", "ServiceManagement",
                       "-framework", "Vision", "-framework", "NaturalLanguage", "-lsqlite3"]
            compiled = subprocess.run(command, env=env, cwd=REPO, capture_output=True, text=True, timeout=90)
            (HERE / "provider-icon-probe-compile.log").write_text(compiled.stdout + compiled.stderr)
            compiled.check_returncode()
            result = temp / "result.json"
            run = subprocess.run([str(executable), f"http://localhost:{server.server_port}/", str(temp / "icons"), str(result)],
                                 env=env, cwd=REPO, capture_output=True, text=True, timeout=120)
            (HERE / "provider-icon-probe-process.log").write_text(run.stdout + run.stderr)
            run.check_returncode()
            output = json.loads(result.read_text())
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        (HERE / "provider-icon-probe-http.json").write_text(json.dumps(REQUESTS, indent=2, sort_keys=True) + "\n")

    counts = collections.Counter(request["path"] for request in REQUESTS)
    network_checks = {
        "relative_icon_resolved": counts["/relative/assets/icon.png"] == 1,
        "homepage_and_icon_redirects_followed": all(counts[path] == 1 for path in ["/redirect/", "/redirected/page/", "/redirected/assets/icon.png", "/images/redirect.png"]),
        "fallback_always_requested": counts["/fallback/favicon.ico"] == 1 and sum(counts[f"/fallback/broken-{i}.png"] for i in range(9)) == 7,
        "negative_cache_prevents_repeat_requests": counts["/missing/"] == 1 and counts["/missing/favicon.ico"] == 1,
        "concurrent_positive_cache_coalesces_requests": counts["/concurrent/"] == 1 and counts["/concurrent/icon.png"] == 1,
        "privacy_has_no_requests": not any(path.startswith("/suppressed/") for path in counts),
        "no_authorization_or_cookie_headers": not any(request["authorization_present"] or request["cookie_present"] for request in REQUESTS),
    }
    output["http_checks"] = network_checks
    output["metadata"] = metadata
    output["request_counts"] = dict(sorted(counts.items()))
    output["passed"] = not output["failures"] and all(network_checks.values()) and output["windows_shown"] == 0
    (HERE / "provider-icon-probe-results.json").write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"passed": output["passed"], "failures": output["failures"],
                      "http_checks": network_checks, "public_websites": output["public_websites"]}, sort_keys=True))
    return 0 if output["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
