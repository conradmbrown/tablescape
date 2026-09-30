#!/usr/bin/env python3
"""Loopback-only security/transport tests; never contacts the actual game server."""
from __future__ import annotations

import contextlib
import http.client
import http.server
import importlib.util
import io
import json
import pathlib
import os
import secrets
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from dataclasses import replace
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).with_name("native-private-bridge.py")
spec = importlib.util.spec_from_file_location("native_private_bridge", SCRIPT)
bridge = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = bridge
spec.loader.exec_module(bridge)
KEY = secrets.token_hex(32)


class MockGateway(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.respond()

    def do_POST(self):
        self.respond()

    def do_DELETE(self):
        self.respond()

    def respond(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.server.received.append((self.command, self.path, dict(self.headers), body))
        mode = self.server.mode
        if mode == "disconnect":
            self.connection.shutdown(socket.SHUT_RDWR)
            return
        if mode == "redirect":
            self.send_response(302)
            self.send_header("Location", "https://example.invalid/steal")
            self.end_headers()
            return
        content = b"x" * 256 if mode in ("large", "large-unknown") else b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        if mode != "large-unknown":
            self.send_header("Content-Length", "1000" if mode == "truncated" else str(len(content)))
        self.end_headers()
        self.wfile.write(content)


class ConfigurationTests(unittest.TestCase):
    def config(self, **values):
        return replace(bridge.Configuration(key=KEY), **values)

    def test_loopback_is_default(self):
        self.config().validate()
        self.assertEqual(self.config().bind, "127.0.0.1")

    def test_weak_missing_keys_rejected(self):
        for key in ("", "a" * 64, "short", "x" * 64, "01234567" * 4):
            with self.subTest(key_length=len(key)), self.assertRaises(ValueError):
                self.config(key=key).validate()

    def test_public_wildcard_and_names_rejected(self):
        for bind in ("0.0.0.0", "::", "8.8.8.8", "example.com", "169.254.1.2"):
            with self.subTest(bind=bind), self.assertRaises(ValueError):
                self.config(bind=bind, certificate="cert", private_key="key").validate()

    def test_private_bind_requires_tls(self):
        for bind in ("10.23.45.67", "192.168.2.3", "172.16.1.2", "100.64.1.2", "fd00::1"):
            with self.subTest(bind=bind), self.assertRaises(ValueError):
                self.config(bind=bind).validate()
            self.config(bind=bind, certificate="cert", private_key="key").validate()

    def test_upstream_cannot_be_remote_or_contain_credentials(self):
        for upstream in ("http://10.23.45.67:8890", "http://example.com", "http://user:pass@127.0.0.1", "http://127.0.0.1/path", "http://127.0.0.1?token=secret", "ftp://127.0.0.1"):
            with self.subTest(upstream=upstream), self.assertRaises(ValueError):
                self.config(upstream=upstream).validate()

    def test_known_routes_only(self):
        allowed = (("GET", "/health"), ("GET", "/v1/state"), ("POST", "/v1/session"),
                   ("POST", "/v1/action"), ("DELETE", "/v1/session"), ("GET", "/v1/models/123"),
                   ("GET", "/v1/audio/music/100?loops=8"), ("GET", "/v1/chunk?x=3200&z=3200&level=0"),
                   ("GET", "/v1/overlay/" + "a" * 64))
        for method, path in allowed:
            with self.subTest(method=method, path=path):
                self.assertTrue(bridge.route_allowed(method, path))
        denied = (("GET", "/admin"), ("GET", "/v1/../admin"), ("GET", "/v1/%2e%2e/admin"),
                  ("GET", "http://127.0.0.1/health"), ("GET", "//[broken"), ("POST", "/v1/state"),
                  ("GET", "/health?token=secret"), ("GET", "/v1/audio/music/1?loops=9"),
                  ("GET", "/v1/chunk?x=1&x=2&z=3&level=0"), ("GET", "/v1/chunk?x=1&z=3&level=4"))
        for method, path in denied:
            with self.subTest(method=method, path=path):
                self.assertFalse(bridge.route_allowed(method, path))


class TransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gateway = http.server.ThreadingHTTPServer(("127.0.0.1", 0), MockGateway)
        cls.gateway.received = []
        cls.gateway.mode = "normal"
        cls.gateway_thread = threading.Thread(target=cls.gateway.serve_forever, daemon=True)
        cls.gateway_thread.start()
        cls.config = bridge.Configuration(port=0, key=KEY, upstream=f"http://127.0.0.1:{cls.gateway.server_port}")
        cls.server = bridge.BridgeServer(cls.config)
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close()
        cls.gateway.shutdown(); cls.gateway.server_close()
        cls.server_thread.join(); cls.gateway_thread.join()

    def setUp(self):
        self.gateway.received.clear()
        self.gateway.mode = "normal"

    def request(self, method="GET", path="/health", body=None, headers=None, key=KEY):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        combined = {} if key is None else {bridge.KEY_HEADER: key}
        if headers: combined.update(headers)
        connection.request(method, path, body=body, headers=combined)
        response = connection.getresponse()
        result = response.status, response.read(), dict(response.headers)
        connection.close()
        return result

    def test_missing_and_wrong_auth_never_reach_gateway(self):
        for key in (None, secrets.token_hex(32)):
            self.assertEqual(self.request(key=key)[0], 401)
        self.assertEqual(self.gateway.received, [])

    def test_game_bearer_separate_and_bridge_key_not_forwarded(self):
        result = self.request(headers={"Authorization": "Bearer test-session", "Cookie": "private=1", "X-Forwarded-For": "8.8.8.8"})
        self.assertEqual(result[0], 200)
        headers = {k.lower(): v for k, v in self.gateway.received[0][2].items()}
        self.assertEqual(headers["authorization"], "Bearer test-session")
        for name in (bridge.KEY_HEADER.lower(), "cookie", "x-forwarded-for"):
            self.assertNotIn(name, headers)
        self.assertEqual(result[2]["Cache-Control"], "no-store")

    def test_action_forwarded_exactly_once(self):
        body = b'{"kind":"move","x":3200,"z":3200}'
        result = self.request("POST", "/v1/action", body, {"Content-Type": "application/json", "Authorization": "Bearer test-session"})
        self.assertEqual(result[0], 200)
        self.assertEqual(len(self.gateway.received), 1)
        self.assertEqual(self.gateway.received[0][3], body)

    def test_uncertain_action_is_not_retried(self):
        self.gateway.mode = "disconnect"
        result = self.request("POST", "/v1/action", b'{"kind":"move"}', {"Content-Type": "application/json"})
        self.assertEqual(result[0], 502)
        self.assertEqual(json.loads(result[1])["code"], "GATEWAY_UNCERTAIN")
        self.assertEqual(len(self.gateway.received), 1)

    def test_redirect_not_followed_or_returned(self):
        self.gateway.mode = "redirect"
        result = self.request()
        self.assertEqual(result[0], 502)
        self.assertNotIn("Location", result[2])
        self.assertEqual(len(self.gateway.received), 1)

    def test_browser_origin_rejected(self):
        self.assertEqual(self.request(headers={"Origin": "https://example.invalid"})[0], 403)
        self.assertEqual(self.gateway.received, [])

    def test_unknown_route_rejected(self):
        self.assertEqual(self.request(path="/admin")[0], 404)
        self.assertEqual(self.gateway.received, [])

    def test_oversized_or_invalid_request_body_rejected(self):
        for body, content_type, expected in ((b"x" * 2049, "application/json", 413), (b"{broken", "application/json", 400), (b"[]", "application/json", 400), (b"{}", "text/plain", 415)):
            self.assertEqual(self.request("POST", "/v1/action", body, {"Content-Type": content_type})[0], expected)
        self.assertEqual(self.gateway.received, [])

    def test_duplicate_framing_and_transfer_encoding_rejected(self):
        for header, values in (("Content-Length", ["0", "0"]), ("Authorization", ["Bearer first", "Bearer second"]), ("Transfer-Encoding", ["chunked"])):
            connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
            connection.putrequest("GET", "/health")
            connection.putheader(bridge.KEY_HEADER, KEY)
            for value in values: connection.putheader(header, value)
            connection.endheaders()
            response = connection.getresponse()
            self.assertEqual(response.status, 400)
            response.read(); connection.close()
        self.assertEqual(self.gateway.received, [])

    def test_oversized_and_truncated_upstream_rejected(self):
        for mode in ("large", "large-unknown", "truncated"):
            with self.subTest(mode=mode), patch.object(bridge, "MAX_RESPONSE", 128):
                self.gateway.mode = mode
                self.assertEqual(self.request()[0], 502)

    def test_secrets_not_logged(self):
        output = io.StringIO()
        with contextlib.redirect_stderr(output), contextlib.redirect_stdout(output):
            self.request(key="wrong-secret-never-log")
            self.request(headers={"Authorization": "Bearer game-secret-never-log"})
        self.assertEqual(output.getvalue(), "")

    def test_tls_loopback_transport(self):
        storage_spec = importlib.util.spec_from_file_location("validate_storage", SCRIPT.with_name("validate-storage.py"))
        storage_module = importlib.util.module_from_spec(storage_spec)
        storage_spec.loader.exec_module(storage_module)
        scratch = storage_module.validate() / "BridgeTests"
        storage_module.validate([str(scratch)])
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            certificate, private_key = pathlib.Path(directory) / "cert.pem", pathlib.Path(directory) / "key.pem"
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1", "-keyout", str(private_key), "-out", str(certificate)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            config = replace(self.config, certificate=str(certificate), private_key=str(private_key))
            server = bridge.BridgeServer(config)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                context = ssl.create_default_context(cafile=str(certificate))
                connection = http.client.HTTPSConnection("127.0.0.1", server.server_port, context=context, timeout=3)
                connection.request("GET", "/health", headers={bridge.KEY_HEADER: KEY})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read()), {"ok": True})
                connection.close()
            finally:
                server.shutdown(); server.server_close(); thread.join()


if __name__ == "__main__":
    unittest.main(verbosity=2)
