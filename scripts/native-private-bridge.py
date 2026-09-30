#!/usr/bin/env python3
"""Private native-client bridge. No discovery, public listener, or retry behavior."""
from __future__ import annotations

import argparse
import hmac
import http.client
import http.server
import ipaddress
import json
import os
import re
import socket
import ssl
import threading
from dataclasses import dataclass
from urllib.parse import parse_qsl, urlsplit

KEY_HEADER = "X-TableScape-Bridge-Key"
KEY_ENV = "SCAPE_BRIDGE_KEY"
MAX_BODY = 2048  # Matches UnityGateway's action/session JSON limit.
MAX_HEADERS = 16384
MAX_RESPONSE = 16_000_000
MAX_AUDIO = 64_000_000
PRIVATE_NETWORKS = tuple(ipaddress.ip_network(value) for value in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "fc00::/7"))


@dataclass(frozen=True)
class Configuration:
    bind: str = "127.0.0.1"
    port: int = 18891
    upstream: str = "http://127.0.0.1:18890"
    key: str = ""
    certificate: str | None = None
    private_key: str | None = None
    max_connections: int = 4

    def validate(self) -> None:
        try:
            address = ipaddress.ip_address(self.bind)
        except ValueError as exc:
            raise ValueError("Bind must be a literal loopback or private IP address.") from exc
        private = address.is_loopback or any(address in network for network in PRIVATE_NETWORKS)
        if address.is_unspecified or not private:
            raise ValueError("Wildcard and public bind addresses are prohibited.")
        if not 0 <= self.port <= 65535 or not 1 <= self.max_connections <= 8:
            raise ValueError("Port or connection limit is out of range.")
        if not re.fullmatch(r"[a-fA-F0-9]{64}", self.key) or len(set(self.key.lower())) < 8:
            raise ValueError(f"{KEY_ENV} must contain a generated 256-bit key: 64 random hexadecimal characters.")
        if bool(self.certificate) != bool(self.private_key):
            raise ValueError("TLS requires both --certificate and --private-key.")
        if not address.is_loopback and not self.certificate:
            raise ValueError("A private-network listener requires TLS certificate and private key; termination bypass is unsupported.")
        target = urlsplit(self.upstream)
        try:
            upstream_address = ipaddress.ip_address(target.hostname or "")
            upstream_port = target.port
        except ValueError as exc:
            raise ValueError("Upstream must use a literal loopback IP and valid port.") from exc
        if (target.scheme not in ("http", "https") or not upstream_address.is_loopback
                or target.username is not None or target.password is not None
                or target.path not in ("", "/") or target.query or target.fragment
                or upstream_port is not None and not 1 <= upstream_port <= 65535):
            raise ValueError("Upstream must be an HTTP(S) loopback origin without credentials, path, query, or fragment.")


def route_allowed(method: str, target: str) -> bool:
    if len(target) > 512 or not target.startswith("/") or target.startswith("//"):
        return False
    try:
        parsed = urlsplit(target)
    except ValueError:
        return False
    if parsed.scheme or parsed.netloc or parsed.fragment or "%" in parsed.path or "\\" in parsed.path:
        return False
    try:
        pairs = parse_qsl(parsed.query, keep_blank_values=True, strict_parsing=True, max_num_fields=4) if parsed.query else []
    except ValueError:
        return False
    query = dict(pairs)
    if len(query) != len(pairs):
        return False
    if method in ("POST", "DELETE"):
        return not query and ((method == "POST" and parsed.path in ("/v1/session", "/v1/action"))
                              or (method == "DELETE" and parsed.path == "/v1/session"))
    if method != "GET":
        return False
    if parsed.path == "/v1/chunk":
        return (set(query) == {"x", "z", "level"}
                and all(re.fullmatch(r"-?\d{1,6}", query[key]) for key in ("x", "z"))
                and query["level"] in ("0", "1", "2", "3"))
    if re.fullmatch(r"/v1/audio/(sound|music)/\d{1,5}", parsed.path):
        return not query or (set(query) == {"loops"} and query["loops"] in tuple(str(i) for i in range(1, 9)))
    if query:
        return False
    return (parsed.path in ("/health", "/v1/state", "/v1/terrain")
            or re.fullmatch(r"/v1/(models|textures|sequence)/\d{1,5}", parsed.path) is not None
            or re.fullmatch(r"/v1/overlay/[a-f0-9]{64}", parsed.path) is not None)


class BridgeServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 8
    allow_reuse_address = True

    def __init__(self, config: Configuration):
        config.validate()
        self.config = config
        self.slots = threading.BoundedSemaphore(config.max_connections)
        self.tls: ssl.SSLContext | None = None
        if config.certificate:
            self.tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            self.tls.minimum_version = ssl.TLSVersion.TLSv1_2
            self.tls.load_cert_chain(config.certificate, config.private_key)
        if ipaddress.ip_address(config.bind).version == 6:
            self.address_family = socket.AF_INET6
        super().__init__((config.bind, config.port), BridgeHandler)

    def process_request(self, request: socket.socket, client_address: tuple) -> None:
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request: socket.socket, client_address: tuple) -> None:
        try:
            request.settimeout(10)
            if self.tls:
                request = self.tls.wrap_socket(request, server_side=True)
            self.finish_request(request, client_address)
        except (OSError, ValueError, http.client.HTTPException):
            pass  # Never log request data, paths, bridge keys, or game bearer tokens.
        finally:
            self.shutdown_request(request)
            self.slots.release()

    def handle_error(self, request: socket.socket, client_address: tuple) -> None:
        pass


class BridgeHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "TableScapeBridge"
    sys_version = ""

    def log_message(self, format: str, *args: object) -> None:
        pass

    def handle_expect_100(self) -> bool:
        self.send_error(417)
        return False

    def send_error(self, code: int, message: str | None = None, explain: str | None = None) -> None:
        self.reply(code, {"error": self.responses.get(code, ("Request failed", ""))[0]})

    def reply(self, code: int, payload: dict) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode()
        self.respond(code, "application/json", data)

    def respond(self, code: int, content_type: str, data: bytes) -> None:
        self.close_connection = True
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        self.proxy()

    def do_POST(self) -> None:
        self.proxy()

    def do_DELETE(self) -> None:
        self.proxy()

    def proxy(self) -> None:
        config = self.server.config
        self.close_connection = True  # One parsed request per socket; no pipelining.
        if sum(len(key) + len(value) + 4 for key, value in self.headers.items()) > MAX_HEADERS:
            self.reply(431, {"error": "Request headers too large"})
            return
        presented = self.headers.get_all(KEY_HEADER, [])
        if len(presented) != 1 or not hmac.compare_digest(presented[0].encode("utf-8"), config.key.encode("ascii")):
            self.reply(401, {"error": "Bridge authentication required", "code": "BRIDGE_AUTH_REQUIRED"})
            return
        if self.headers.get("Origin") is not None:
            self.reply(403, {"error": "Native clients only"})
            return
        if not route_allowed(self.command, self.path):
            self.reply(404, {"error": "Route unavailable"})
            return
        if (self.headers.get("Transfer-Encoding") is not None
                or any(len(self.headers.get_all(name, [])) > 1 for name in ("Content-Length", "Authorization", "Content-Type"))):
            self.reply(400, {"error": "Ambiguous request framing"})
            return
        raw_length = self.headers.get("Content-Length", "0")
        if not re.fullmatch(r"\d{1,8}", raw_length):
            self.reply(400, {"error": "Invalid content length"})
            return
        length = int(raw_length)
        if length > MAX_BODY or (self.command != "POST" and length != 0):
            self.reply(413, {"error": "Request body too large or unsupported"})
            return
        if self.command == "POST" and self.headers.get_content_type() != "application/json":
            self.reply(415, {"error": "JSON request body required"})
            return
        try:
            body = self.rfile.read(length)
            if len(body) != length:
                self.reply(400, {"error": "Incomplete request body"})
                return
            if self.command == "POST" and not isinstance(json.loads(body or b"{}"), dict):
                self.reply(400, {"error": "JSON object required"})
                return
        except (ValueError, OSError):
            self.reply(400, {"error": "Invalid or incomplete request body"})
            return
        target = urlsplit(config.upstream)
        headers = {"Accept": "*/*", "Accept-Encoding": "identity", "Connection": "close"}
        if self.command == "POST":
            headers["Content-Type"] = "application/json"
        if self.headers.get("Authorization"):
            headers["Authorization"] = self.headers["Authorization"]
        # Deliberately exclude the bridge key, cookies, Origin, forwarding headers,
        # client Host, and every other caller-controlled header.
        audio = self.path.startswith("/v1/audio/")
        limit = MAX_AUDIO if audio else MAX_RESPONSE
        connection_type = http.client.HTTPSConnection if target.scheme == "https" else http.client.HTTPConnection
        connection = connection_type(target.hostname, target.port, timeout=65 if audio else 15)
        try:
            # Exactly one upstream attempt, including mutations. No redirect following.
            connection.request(self.command, self.path, body=body if self.command == "POST" else None, headers=headers)
            response = connection.getresponse()
            if 300 <= response.status < 400:
                self.reply(502, {"error": "Gateway redirect refused"})
                return
            declared = response.getheader("Content-Length")
            if declared is not None and (not re.fullmatch(r"\d{1,10}", declared) or int(declared) > limit):
                self.reply(502, {"error": "Gateway response exceeds limit"})
                return
            data = response.read(limit + 1)
            if len(data) > limit or (declared is not None and len(data) != int(declared)):
                self.reply(502, {"error": "Gateway response exceeds limit"})
                return
            content_type = response.getheader("Content-Type", "application/octet-stream")
            if "\r" in content_type or "\n" in content_type:
                content_type = "application/octet-stream"
            self.respond(response.status, content_type, data)
        except (OSError, ValueError, http.client.HTTPException):
            self.reply(502, {"error": "Gateway unavailable; an attempted action was not retried", "code": "GATEWAY_UNCERTAIN"})
        finally:
            connection.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18891)
    parser.add_argument("--upstream", default="http://127.0.0.1:18890")
    parser.add_argument("--certificate")
    parser.add_argument("--private-key")
    parser.add_argument("--max-connections", type=int, default=4)
    args = parser.parse_args()
    try:
        config = Configuration(**vars(args), key=os.environ.get(KEY_ENV, ""))
        server = BridgeServer(config)
    except (ValueError, OSError, ssl.SSLError) as error:
        parser.exit(2, f"Bridge configuration failed: {error}\n")
    protocol = "https" if server.tls else "http"
    print(f"TableScape private bridge listening at {protocol}://{config.bind}:{server.server_port}; upstream loopback; no request logging.", flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
