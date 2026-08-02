"""
Minimal HTTP server for Kubernetes liveness/readiness probes.

Same pattern as stream-processor: this service is a background worker,
not an HTTP service, but K8s probes need something to hit over HTTP.
"""

import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

_is_healthy = True


def mark_unhealthy():
    global _is_healthy
    _is_healthy = False


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health" and _is_healthy:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
        else:
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b'{"status": "unhealthy"}')

    def log_message(self, format, *args):
        pass


def start_health_server(port=8080):
    server = HTTPServer(("0.0.0.0", port), HealthHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server
