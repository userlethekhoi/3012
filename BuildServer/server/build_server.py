#!/usr/bin/env python3
"""
3012 Theos Build Server
-----------------------
Accepts a zipped Theos project from the 3012 iOS app, queues it, and builds it inside a
throw-away, network-less, unprivileged Docker container. Only the build log and the
resulting .deb / .dylib are returned. Users never get a shell on the host.

Standard library only (Python 3.10+). Listens on 127.0.0.1 and is exposed to the
Internet exclusively through a Cloudflare Tunnel, so the host IP is never revealed.
"""

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import threading
import time
import uuid
from collections import defaultdict, deque
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

VERSION = "1.0.0"


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


CFG = {
    "bind": os.environ.get("BUILD_BIND", "127.0.0.1"),
    "port": _env_int("BUILD_PORT", 8787),
    "image": os.environ.get("BUILD_IMAGE", "3012-theos-builder:latest"),
    "concurrency": max(1, _env_int("BUILD_CONCURRENCY", 2)),
    "max_queue": _env_int("BUILD_MAX_QUEUE", 30),
    "max_upload": _env_int("BUILD_MAX_UPLOAD_MB", 20) * 1024 * 1024,
    "timeout": _env_int("BUILD_TIMEOUT_SEC", 120),
    "memory": os.environ.get("BUILD_MEMORY", "1g"),
    "cpus": os.environ.get("BUILD_CPUS", "1.5"),
    "rate_device": _env_int("BUILD_RATE_PER_DEVICE_HOUR", 20),
    "rate_ip": _env_int("BUILD_RATE_PER_IP_HOUR", 40),
    "data_dir": os.environ.get("BUILD_DATA_DIR", "/var/lib/3012-build"),
    "artifact_ttl": _env_int("BUILD_ARTIFACT_TTL_SEC", 900),
    "runtime": os.environ.get("BUILD_RUNTIME", "").strip(),
    "disk_max_percent": _env_int("BUILD_DISK_MAX_PERCENT", 90),
    "trust_cf_header": os.environ.get("BUILD_TRUST_CF_HEADER", "1") == "1",
    "max_log": 512 * 1024,
    "max_artifact_bytes": 100 * 1024 * 1024,
}

JOB_ID_RE = re.compile(r"^[a-f0-9]{32}$")
DEVICE_RE = re.compile(r"^[A-Za-z0-9-]{8,64}$")
FILE_RE = re.compile(r"^[A-Za-z0-9._+~-]{1,160}$")
ALLOWED_EXT = (".deb", ".dylib")
SCHEMES = {"rootless", "rootful", "roothide"}


def log(msg: str) -> None:
    sys.stdout.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    sys.stdout.flush()


def short_hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()[:10]


# --------------------------------------------------------------------------- Jobs


class Job:
    def __init__(self, device: str, ip: str, scheme: str, payload: bytes):
        self.id = uuid.uuid4().hex
        self.device = device
        self.ip = ip
        self.scheme = scheme
        self.payload = payload
        self.state = "queued"  # queued | running | succeeded | failed | cancelled
        self.log = bytearray()
        self.log_truncated = False
        self.files = []
        self.exit_code = None
        self.error = None
        self.created = time.time()
        self.started = None
        self.finished = None
        self.cancel_requested = False
        self.lock = threading.Lock()

    @property
    def container_name(self) -> str:
        return "b3012-" + self.id[:16]

    def append_log(self, chunk: bytes) -> None:
        with self.lock:
            room = CFG["max_log"] - len(self.log)
            if room <= 0:
                self.log_truncated = True
                return
            self.log += chunk[:room]
            if len(chunk) > room:
                self.log_truncated = True

    def log_since(self, offset: int):
        with self.lock:
            total = len(self.log)
            offset = max(0, min(offset, total))
            data = bytes(self.log[offset:])
        if self.state in ("queued", "running"):
            cut = data.rfind(b"\n")
            data = data[: cut + 1] if cut >= 0 else b""
        return data.decode("utf-8", "replace"), offset + len(data)


class BuildQueue:
    def __init__(self):
        self.jobs = {}
        self.pending = deque()
        self.running = set()
        self.cond = threading.Condition()
        self.rate = defaultdict(deque)

    # Rate limiting -----------------------------------------------------------
    def _allow(self, key: str, limit: int) -> bool:
        if limit <= 0:
            return True
        now = time.time()
        window = self.rate[key]
        while window and now - window[0] > 3600:
            window.popleft()
        if len(window) >= limit:
            return False
        window.append(now)
        return True

    def submit(self, device: str, ip: str, scheme: str, payload: bytes):
        with self.cond:
            if len(self.pending) >= CFG["max_queue"]:
                return None, ("queue_full", "Máy chủ đang quá tải. Vui lòng thử lại sau hoặc dùng phương thức build khác.")
            if not self._allow("d:" + device, CFG["rate_device"]):
                return None, ("rate_limited", f"Thiết bị đã đạt giới hạn {CFG['rate_device']} lần build/giờ.")
            if not self._allow("i:" + ip, CFG["rate_ip"]):
                return None, ("rate_limited", f"Mạng của bạn đã đạt giới hạn {CFG['rate_ip']} lần build/giờ.")
            job = Job(device, ip, scheme, payload)
            self.jobs[job.id] = job
            self.pending.append(job)
            self.cond.notify()
            return job, None

    def position(self, job: Job) -> int:
        with self.cond:
            try:
                return list(self.pending).index(job) + 1
            except ValueError:
                return 0

    def next_job(self) -> Job:
        with self.cond:
            while not self.pending:
                self.cond.wait()
            job = self.pending.popleft()
            self.running.add(job.id)
            return job

    def done(self, job: Job) -> None:
        with self.cond:
            self.running.discard(job.id)

    def cancel(self, job: Job) -> None:
        with self.cond:
            job.cancel_requested = True
            if job in self.pending:
                self.pending.remove(job)
                job.state = "cancelled"
                job.payload = None
                job.finished = time.time()
                return
        if job.state == "running":
            subprocess.run(["docker", "kill", job.container_name], capture_output=True, timeout=20)

    def stats(self):
        with self.cond:
            return {"queued": len(self.pending), "running": len(self.running), "capacity": CFG["concurrency"]}

    def cleanup(self) -> None:
        now = time.time()
        with self.cond:
            expired = [j for j in self.jobs.values()
                       if j.finished and now - j.finished > CFG["artifact_ttl"]]
            for job in expired:
                del self.jobs[job.id]
            for key in [k for k, w in self.rate.items() if not w or now - w[-1] > 3600]:
                del self.rate[key]
        for job in expired:
            shutil.rmtree(artifact_dir(job.id), ignore_errors=True)


QUEUE = BuildQueue()


def artifact_dir(job_id: str) -> str:
    return os.path.join(CFG["data_dir"], "artifacts", job_id)


# --------------------------------------------------------------------------- Worker


def docker_command(job: Job):
    cmd = [
        "docker", "run", "--rm", "-i",
        "--name", job.container_name,
        "--hostname", "builder",
        "--network", "none",
        "--read-only",
        "--tmpfs", "/work:rw,exec,nosuid,nodev,size=768m,uid=1000,gid=1000,mode=0700",
        "--tmpfs", "/tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000,mode=1777",
        "--user", "1000:1000",
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--pids-limit", "256",
        "--memory", CFG["memory"],
        "--memory-swap", CFG["memory"],
        "--cpus", CFG["cpus"],
        "--ulimit", "nofile=1024:1024",
        "--ulimit", "fsize=268435456:268435456",
        "--log-driver", "none",
        "-e", "PACKAGE_SCHEME=" + job.scheme,
    ]
    if CFG["runtime"]:
        cmd += ["--runtime", CFG["runtime"]]
    cmd.append(CFG["image"])
    return cmd


def run_job(job: Job) -> None:
    job.state = "running"
    job.started = time.time()
    job.append_log(f"[3012] Bắt đầu build (scheme: {job.scheme}, giới hạn {CFG['timeout']}s, RAM {CFG['memory']}).\n".encode())

    proc = subprocess.Popen(docker_command(job), stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    payload, job.payload = job.payload, None

    def feed():
        try:
            proc.stdin.write(payload)
        except (BrokenPipeError, OSError):
            pass
        finally:
            try:
                proc.stdin.close()
            except OSError:
                pass

    def pump_log():
        for line in iter(proc.stderr.readline, b""):
            job.append_log(line)

    out = bytearray()

    def pump_out():
        while True:
            chunk = proc.stdout.read(65536)
            if not chunk:
                break
            if len(out) < CFG["max_artifact_bytes"]:
                out.extend(chunk)

    threads = [threading.Thread(target=t, daemon=True) for t in (feed, pump_log, pump_out)]
    for t in threads:
        t.start()

    timed_out = False
    try:
        proc.wait(timeout=CFG["timeout"])
    except subprocess.TimeoutExpired:
        timed_out = True
        subprocess.run(["docker", "kill", job.container_name], capture_output=True, timeout=20)
        proc.wait(timeout=30)
    for t in threads:
        t.join(timeout=10)

    job.exit_code = proc.returncode
    files = extract_artifacts(job, bytes(out))
    job.files = files

    if job.cancel_requested:
        job.state = "cancelled"
        job.append_log("\n[3012] Build đã bị huỷ.\n".encode())
    elif timed_out:
        job.state = "failed"
        job.error = "timeout"
        job.append_log(f"\n[3012] Quá thời gian {CFG['timeout']} giây — build đã bị dừng.\n".encode())
    elif proc.returncode == 0 and files:
        job.state = "succeeded"
        job.append_log(("\n[3012] Build thành công: " + ", ".join(f["name"] for f in files) + "\n").encode())
    else:
        job.state = "failed"
        job.error = "build_failed" if proc.returncode not in (125, 126, 127) else "runner_error"
        if proc.returncode == 137:
            job.append_log(f"\n[3012] Build bị dừng do vượt giới hạn RAM ({CFG['memory']}).\n".encode())
        job.append_log(f"\n[3012] Build thất bại (exit code {proc.returncode}).\n".encode())
    job.finished = time.time()
    log(f"job={job.id[:8]} device={short_hash(job.device)} state={job.state} "
        f"exit={job.exit_code} secs={job.finished - job.started:.1f}")


def extract_artifacts(job: Job, data: bytes):
    if not data:
        return []
    target = artifact_dir(job.id)
    os.makedirs(target, exist_ok=True)
    files = []
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as tar:
            for member in tar:
                if not member.isfile():
                    continue
                name = os.path.basename(member.name)
                if not FILE_RE.match(name) or not name.endswith(ALLOWED_EXT):
                    continue
                if member.size > CFG["max_artifact_bytes"]:
                    continue
                src = tar.extractfile(member)
                if src is None:
                    continue
                path = os.path.join(target, name)
                with open(path, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                files.append({"name": name, "size": member.size})
    except tarfile.TarError:
        job.append_log("[3012] Không đọc được kết quả build.\n".encode())
    return files


def worker_loop() -> None:
    while True:
        job = QUEUE.next_job()
        try:
            if job.cancel_requested:
                continue
            run_job(job)
        except Exception as exc:  # never let a worker die
            job.state = "failed"
            job.error = "internal_error"
            job.finished = time.time()
            job.append_log(f"\n[3012] Lỗi nội bộ máy chủ: {type(exc).__name__}\n".encode())
            log(f"job={job.id[:8]} internal error: {exc!r}")
        finally:
            QUEUE.done(job)


def janitor_loop() -> None:
    while True:
        time.sleep(60)
        try:
            QUEUE.cleanup()
        except Exception as exc:
            log(f"janitor error: {exc!r}")


# --------------------------------------------------------------------------- HTTP API


def disk_usage_percent() -> int:
    usage = shutil.disk_usage(CFG["data_dir"])
    return int(usage.used * 100 / usage.total)


class Handler(BaseHTTPRequestHandler):
    server_version = "3012-build/" + VERSION
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet: no IPs or payloads in logs
        pass

    # Helpers -----------------------------------------------------------------
    def client_ip(self) -> str:
        if CFG["trust_cf_header"]:
            cf = self.headers.get("CF-Connecting-IP", "").strip()
            if cf:
                return cf
        return self.client_address[0]

    def send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def error(self, status: int, code: str, message: str) -> None:
        self.send_json(status, {"error": code, "message": message})

    def find_job(self, job_id: str):
        if not JOB_ID_RE.match(job_id):
            return None
        return QUEUE.jobs.get(job_id)

    def job_view(self, job: Job, since: int):
        text, next_offset = job.log_since(since)
        return {
            "id": job.id,
            "state": job.state,
            "position": QUEUE.position(job) if job.state == "queued" else 0,
            "log": text,
            "logOffset": next_offset,
            "logTruncated": job.log_truncated,
            "exitCode": job.exit_code,
            "error": job.error,
            "files": job.files,
            "elapsed": round((job.finished or time.time()) - (job.started or time.time()), 1),
        }

    def send_html(self, status: int, html_body: str) -> None:
        data = html_body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    # Routes ------------------------------------------------------------------
    def do_GET(self):
        url = urlparse(self.path)
        parts = [p for p in url.path.split("/") if p]
        if parts == []:
            stats = QUEUE.stats()
            if "text/html" in self.headers.get("Accept", "").lower():
                html_doc = f"""<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>3012 Theos Build Server</title>
<style>
  body{{margin:0;background:#0A0D12;color:#F1F5F9;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;display:grid;place-items:center;min-height:100vh;padding:24px}}
  .card{{max-width:540px;width:100%;background:#141A22;border:1px solid #263040;border-radius:12px;padding:24px;box-sizing:border-box}}
  .badge{{display:inline-block;padding:4px 10px;border-radius:6px;background:rgba(16,185,129,.16);color:#10B981;font-size:12px;font-weight:700;letter-spacing:.04em}}
  h1{{margin:14px 0 8px;font-size:20px}}
  p{{color:#94A3B8;font-size:13px;line-height:1.55}}
  .grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:18px 0}}
  .stat{{background:#0D1117;border:1px solid #1E293B;border-radius:8px;padding:10px}}
  .stat b{{display:block;font-size:18px;color:#F8FAFC;margin-top:4px}}
  .stat span{{font-size:11px;color:#64748B;text-transform:uppercase}}
  code{{background:#0D1117;padding:2px 6px;border-radius:4px;color:#E2E8F0}}
</style>
</head>
<body>
  <div class="card">
    <span class="badge">3012 BUILD SERVER v{VERSION} — ONLINE</span>
    <h1>Theos Remote Compiler Sandbox</h1>
    <p>Máy chủ biên dịch <code>.deb</code> / <code>.dylib</code> cách ly bằng Docker cho ứng dụng iOS <strong>3012</strong>.</p>
    <div class="grid">
      <div class="stat"><span>Đang build</span><b>{stats["running"]} / {stats["capacity"]}</b></div>
      <div class="stat"><span>Hàng đợi</span><b>{stats["queued"]}</b></div>
      <div class="stat"><span>Timeout</span><b>{CFG["timeout"]}s</b></div>
    </div>
    <p>Sandbox: <code>--network none</code> • <code>--read-only</code> • <code>uid 1000</code><br/>Endpoint API: <code>/v1/health</code> • <code>POST /v1/builds</code></p>
  </div>
</body>
</html>"""
                return self.send_html(200, html_doc)
            body = {"ok": True, "version": VERSION, **stats,
                    "limits": {"maxUploadMB": CFG["max_upload"] // (1024 * 1024),
                               "timeoutSec": CFG["timeout"],
                               "perDeviceHour": CFG["rate_device"]}}
            return self.send_json(200, body)
        if parts == ["v1", "health"]:
            body = {"ok": True, "version": VERSION, **QUEUE.stats(),
                    "limits": {"maxUploadMB": CFG["max_upload"] // (1024 * 1024),
                               "timeoutSec": CFG["timeout"],
                               "perDeviceHour": CFG["rate_device"]}}
            return self.send_json(200, body)
        if len(parts) == 3 and parts[:2] == ["v1", "builds"]:
            job = self.find_job(parts[2])
            if not job:
                return self.error(404, "not_found", "Không tìm thấy build (có thể đã hết hạn).")
            since = 0
            try:
                since = int(parse_qs(url.query).get("since", ["0"])[0])
            except ValueError:
                pass
            return self.send_json(200, self.job_view(job, since))
        if len(parts) == 5 and parts[:2] == ["v1", "builds"] and parts[3] == "files":
            job = self.find_job(parts[2])
            name = parts[4]
            if not job or not FILE_RE.match(name) or name not in {f["name"] for f in job.files}:
                return self.error(404, "not_found", "Không tìm thấy file.")
            if self.headers.get("X-Device-ID", "") != job.device:
                return self.error(403, "forbidden", "Không có quyền tải file này.")
            path = os.path.join(artifact_dir(job.id), name)
            try:
                size = os.path.getsize(path)
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(size))
                self.send_header("Content-Disposition", f'attachment; filename="{name}"')
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                with open(path, "rb") as fh:
                    shutil.copyfileobj(fh, self.wfile)
            except OSError:
                return self.error(410, "gone", "File đã hết hạn.")
            return None
        return self.error(404, "not_found", "Endpoint không tồn tại.")

    def do_POST(self):
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        if parts != ["v1", "builds"]:
            return self.error(404, "not_found", "Endpoint không tồn tại.")

        device = self.headers.get("X-Device-ID", "").strip()
        if not DEVICE_RE.match(device):
            return self.error(400, "bad_device", "Thiếu hoặc sai X-Device-ID.")
        scheme = self.headers.get("X-Package-Scheme", "rootless").strip().lower()
        if scheme not in SCHEMES:
            return self.error(400, "bad_scheme", "X-Package-Scheme phải là rootless, rootful hoặc roothide.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            return self.error(411, "length_required", "Thiếu Content-Length.")
        if length > CFG["max_upload"]:
            self.close_connection = True
            return self.error(413, "too_large", f"Project vượt quá {CFG['max_upload'] // (1024 * 1024)} MB.")
        if disk_usage_percent() >= CFG["disk_max_percent"]:
            self.close_connection = True
            return self.error(503, "disk_full", "Máy chủ tạm ngừng nhận build (ổ đĩa gần đầy).")

        payload = self.rfile.read(length)
        if len(payload) != length or not payload.startswith(b"PK\x03\x04"):
            return self.error(400, "bad_zip", "Dữ liệu tải lên không phải file .zip hợp lệ.")

        job, err = QUEUE.submit(device, self.client_ip(), scheme, payload)
        if err:
            code, message = err
            return self.error(503 if code == "queue_full" else 429, code, message)
        log(f"job={job.id[:8]} device={short_hash(device)} queued size={length}")
        return self.send_json(202, self.job_view(job, 0))

    def do_DELETE(self):
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        if len(parts) != 3 or parts[:2] != ["v1", "builds"]:
            return self.error(404, "not_found", "Endpoint không tồn tại.")
        job = self.find_job(parts[2])
        if not job:
            return self.error(404, "not_found", "Không tìm thấy build.")
        if self.headers.get("X-Device-ID", "") != job.device:
            return self.error(403, "forbidden", "Không có quyền huỷ build này.")
        QUEUE.cancel(job)
        return self.send_json(200, {"id": job.id, "state": job.state})


def main() -> None:
    os.makedirs(os.path.join(CFG["data_dir"], "artifacts"), exist_ok=True)
    # Remove artifacts left over from a previous run.
    for entry in os.listdir(os.path.join(CFG["data_dir"], "artifacts")):
        shutil.rmtree(artifact_dir(entry), ignore_errors=True)
    # Kill stray build containers from a previous run.
    stray = subprocess.run(["docker", "ps", "-q", "--filter", "name=b3012-"], capture_output=True, text=True)
    for cid in stray.stdout.split():
        subprocess.run(["docker", "kill", cid], capture_output=True)

    for _ in range(CFG["concurrency"]):
        threading.Thread(target=worker_loop, daemon=True).start()
    threading.Thread(target=janitor_loop, daemon=True).start()

    server = ThreadingHTTPServer((CFG["bind"], CFG["port"]), Handler)
    server.daemon_threads = True
    log(f"3012 build server {VERSION} listening on {CFG['bind']}:{CFG['port']} "
        f"(concurrency={CFG['concurrency']}, image={CFG['image']})")
    server.serve_forever()


if __name__ == "__main__":
    main()
