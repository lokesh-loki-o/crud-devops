from concurrent.futures import ThreadPoolExecutor
import http.client
import json
import logging
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote

DOCKER_SOCKET = os.environ.get("DOCKER_SOCKET", "/var/run/docker.sock")
DOCKER_API_VERSION = os.environ.get("DOCKER_API_VERSION", "1.41")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, socket_path):
        super().__init__("localhost", timeout=5)
        self.socket_path = socket_path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.socket_path)


def docker_get(path):
    connection = UnixHTTPConnection(DOCKER_SOCKET)
    try:
        connection.request("GET", f"/v{DOCKER_API_VERSION}{path}")
        response = connection.getresponse()
        payload = response.read()
        if response.status != 200:
            raise RuntimeError(
                f"Docker API returned HTTP {response.status}: "
                f"{payload.decode('utf-8', errors='replace')}"
            )
        return json.loads(payload)
    finally:
        connection.close()


def escape_label(value):
    return str(value).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def container_metrics(container):
    container_id = container["Id"]
    names = container.get("Names", [])
    if not names:
        raise RuntimeError(f"Docker returned no name for container {container_id}")
    name = names[0].lstrip("/")
    image = container.get("Image", "")
    labels = (
        f'id="{escape_label(container_id)}",'
        f'name="{escape_label(name)}",'
        f'image="{escape_label(image)}"'
    )
    stats = docker_get(
        f"/containers/{quote(container_id, safe='')}/stats?stream=false"
    )

    try:
        cpu_nanoseconds = stats["cpu_stats"]["cpu_usage"]["total_usage"]
        memory_stats = stats["memory_stats"]
        memory_usage = memory_stats["usage"]
    except KeyError as error:
        raise RuntimeError(
            f"Docker stats missing {error.args[0]} for container {name}"
        ) from error

    memory_details = memory_stats.get("stats", {})
    inactive_file = memory_details.get(
        "inactive_file", memory_details.get("total_inactive_file", 0)
    )
    working_set = max(memory_usage - inactive_file, 0)
    return [
        f"docker_container_cpu_usage_seconds_total{{{labels}}} "
        f"{cpu_nanoseconds / 1_000_000_000}",
        f"docker_container_memory_working_set_bytes{{{labels}}} {working_set}",
    ]


def collect_metrics():
    containers = docker_get("/containers/json")
    metrics = [
        "# HELP docker_containers_running Number of running Docker containers.",
        "# TYPE docker_containers_running gauge",
        f"docker_containers_running {len(containers)}",
        "# HELP docker_container_cpu_usage_seconds_total Cumulative container CPU time in seconds.",
        "# TYPE docker_container_cpu_usage_seconds_total counter",
        "# HELP docker_container_memory_working_set_bytes Container memory usage excluding inactive file cache.",
        "# TYPE docker_container_memory_working_set_bytes gauge",
    ]

    if containers:
        with ThreadPoolExecutor(max_workers=min(len(containers), 8)) as executor:
            for samples in executor.map(container_metrics, containers):
                metrics.extend(samples)

    return "\n".join(metrics) + "\n"


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return

        try:
            body = collect_metrics().encode("utf-8")
        except (http.client.HTTPException, OSError, RuntimeError, ValueError):
            logging.exception("Failed to collect Docker container metrics")
            self.send_error(503, "Docker metrics are temporarily unavailable")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string, *args):
        logging.info("%s - %s", self.address_string(), format_string % args)


if __name__ == "__main__":
    server = ThreadingHTTPServer(
        ("0.0.0.0", int(os.environ.get("PORT", "9100"))), MetricsHandler
    )
    server.serve_forever()
