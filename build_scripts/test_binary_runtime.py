#!/usr/bin/env python3
"""Exercise the native static binary using isolated loopback fixtures."""

import base64
import gzip
import hashlib
import http.server
import json
import os
from pathlib import Path
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request


PAYLOAD = bytes(range(256)) * 1024


class Origin(http.server.BaseHTTPRequestHandler):
    doh_queries = 0

    def log_message(self, *args):
        pass

    def do_GET(self):
        body = gzip.compress(PAYLOAD) if self.path == "/gzip" else PAYLOAD
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        if self.path == "/gzip":
            self.send_header("Content-Encoding", "gzip")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        # RFC 8484 wire-format DNS, answering only our synthetic local origin.
        query = self.rfile.read(int(self.headers["Content-Length"]))
        offset = 12
        while query[offset]:
            offset += query[offset] + 1
        qtype = struct.unpack_from("!H", query, offset + 1)[0]
        question = query[12:offset + 5]
        answer = b""
        if qtype == 1:
            answer = struct.pack("!HHHIH", 0xC00C, 1, 1, 60, 4) + socket.inet_aton("127.0.0.1")
        body = query[:2] + struct.pack("!HHHHH", 0x8180, 1, bool(answer), 0, 0) + question + answer
        Origin.doh_queries += 1
        self.send_response(200)
        self.send_header("Content-Type", "application/dns-message")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def websocket_version(port, secret):
    key = base64.b64encode(os.urandom(16)).decode()
    with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
        connection.sendall((
            f"GET /jsonrpc HTTP/1.1\r\nHost: localhost:{port}\r\n"
            f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode())
        response = b""
        while not response.endswith(b"\r\n\r\n"):
            chunk = connection.recv(1)
            require(chunk, "WebSocket upgrade closed unexpectedly")
            response += chunk
        require(response.startswith(b"HTTP/1.1 101"), "WebSocket upgrade failed")
        expected = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
        ).digest())
        require(expected in response, "WebSocket accept key mismatch")
        payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "aria2.getVersion",
                              "params": [f"token:{secret}"]}).encode()
        require(len(payload) < 126, "WebSocket fixture request too large")
        mask = os.urandom(4)
        connection.sendall(bytes([0x81, 0x80 | len(payload)]) + mask +
                           bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))
        reader = connection.makefile("rb")
        header = reader.read(2)
        require(len(header) == 2 and header[0] == 0x81, "Expected a WebSocket text reply")
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", reader.read(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", reader.read(8))[0]
        reply = json.loads(reader.read(length))
        require("result" in reply and "version" in reply["result"], "WebSocket RPC failed")


def main(binary):
    binary = str(Path(binary).resolve())
    environment = {key: value for key, value in os.environ.items()
                   if key.lower() not in {"http_proxy", "https_proxy", "all_proxy", "no_proxy"}}
    environment["NO_PROXY"] = "*"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with tempfile.TemporaryDirectory(prefix="aria2-runtime-") as temporary:
        root = Path(temporary)
        downloads = root / "downloads"
        downloads.mkdir()
        certificate, key = root / "cert.pem", root / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
            "-keyout", str(key), "-out", str(certificate),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        plain = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        secure = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        secure.socket = context.wrap_socket(secure.socket, server_side=True)
        for server in (plain, secure):
            threading.Thread(target=server.serve_forever, daemon=True).start()
        engine = None
        try:
            base_args = [binary, "--no-conf", f"--dir={downloads}", f"--state-dir={root / 'state'}",
                         "--connect-timeout=3", "--timeout=5", "--max-tries=1", "--retry-wait=0"]

            def download(name, url, extra=(), trusted=False, success=True):
                download_environment = dict(environment)
                if trusted:
                    download_environment["SSL_CERT_FILE"] = str(certificate)
                result = subprocess.run(base_args + [f"--out={name}", *extra, url],
                                        env=download_environment, capture_output=True, timeout=30)
                require((result.returncode == 0) == success,
                        f"{name}: exit {result.returncode}\n"
                        f"{result.stdout.decode(errors='replace')}{result.stderr.decode(errors='replace')}")
                if success:
                    require((downloads / name).read_bytes() == PAYLOAD, f"{name}: payload mismatch")

            download("http.bin", f"http://127.0.0.1:{plain.server_port}/payload")
            download("gzip.bin", f"http://127.0.0.1:{plain.server_port}/gzip")
            tls_url = f"https://localhost:{secure.server_port}/payload"
            download("untrusted.bin", tls_url, success=False)
            download("trusted.bin", tls_url, trusted=True)
            download("doh.bin", f"http://openwrt-origin.invalid:{plain.server_port}/payload",
                     [f"--dns-over-https=https://localhost:{secure.server_port}/dns-query"], trusted=True)
            require(Origin.doh_queries > 0, "DNS-over-HTTPS was not used")

            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            secret = "local-runtime-secret"
            with (root / "engine.log").open("wb") as log:
                engine = subprocess.Popen(base_args + ["--enable-rpc", "--rpc-listen-all=false",
                                                       f"--rpc-listen-port={port}", f"--rpc-secret={secret}",
                                                       "--enable-dht=false", "--bt-enable-lpd=false",
                                                       "--bt-port-mapping=false", "--bt-interface=127.0.0.1"],
                                          stdout=log, stderr=log, env=environment)

                def rpc(method, params=(), token=secret):
                    request = urllib.request.Request(
                        f"http://127.0.0.1:{port}/jsonrpc",
                        data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                                         "params": [f"token:{token}", *params]}).encode(),
                        headers={"Content-Type": "application/json"})
                    return json.loads(opener.open(request, timeout=5).read())

                deadline = time.monotonic() + 10
                while True:
                    require(engine.poll() is None, "RPC engine exited during startup")
                    try:
                        require("result" in rpc("aria2.getVersion"), "RPC getVersion failed")
                        break
                    except (OSError, urllib.error.URLError):
                        require(time.monotonic() < deadline, "RPC startup timed out")
                        time.sleep(0.1)
                try:
                    rejected = "error" in rpc("aria2.getVersion", token="wrong")
                except urllib.error.HTTPError as error:
                    rejected = error.code in (401, 403)
                require(rejected, "RPC accepted an invalid token")
                websocket_version(port, secret)
                require("result" in rpc("aria2.getBtSessionStatus"), "BitTorrent session RPC failed")
                magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
                added = rpc("aria2.addUri", [[magnet]])
                require("result" in added, "BitTorrent task creation failed")
                time.sleep(1)
                require(engine.poll() is None, "BitTorrent session crashed")
                status = rpc("aria2.tellStatus", [added["result"]])
                require(status.get("result", {}).get("status") == "active",
                        f"BitTorrent task did not become active: {status}")
                require("result" in rpc("aria2.shutdown"), "RPC shutdown failed")
                require(engine.wait(timeout=20) == 0, "RPC shutdown returned an error")
            print("Native runtime checks passed: HTTP, gzip, HTTPS trust, DoH, token RPC, WebSocket, BitTorrent.")
        except Exception:
            log_path = root / "engine.log"
            if log_path.exists():
                print(log_path.read_text(errors="replace"), file=sys.stderr)
            raise
        finally:
            if engine and engine.poll() is None:
                engine.terminate()
                try:
                    engine.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    engine.kill()
                    engine.wait()
            for server in (plain, secure):
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: test_binary_runtime.py <native-binary>")
    main(sys.argv[1])
