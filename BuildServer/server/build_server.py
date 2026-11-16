#!/usr/bin/env python3
"""
3012 Theos Build & Zero-Knowledge Sync Relay Server
---------------------------------------------------
1. Accepts a zipped Theos project from the 3012 iOS app, queues it, and builds
   it inside a throw-away, network-less, unprivileged Docker container.
2. Hosts a zero-knowledge end-to-end encrypted WebSocket Relay (`/v1/sync`) for
   2-way real-time file sync between VS Code (PC) and 3012 (iOS) over 4G/5G & Wi-Fi.
   All payloads are encrypted client-side with AES-256-GCM; the server only sees
   opaque base64 blobs and SHA-256 room hashes.
3. Serves `/sync.mjs` for 1-line PC companion sync without Docker or dependencies.

Standard library only (Python 3.10+). Listens on 127.0.0.1 and is exposed to
the Internet exclusively through a Cloudflare Tunnel.
"""

import base64
import hashlib
import io
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import tarfile
import threading
import time
import uuid
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

VERSION = "2.0.0"


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
    "max_project_mb": max(20, _env_int("BUILD_MAX_PROJECT_MB", 300)),
    "max_project_files": max(100, _env_int("BUILD_MAX_PROJECT_FILES", 4000)),
    "cas_batch_bytes": max(1, _env_int("BUILD_CAS_BATCH_MB", 16)) * 1024 * 1024,
    "cas_max_bytes": max(256, _env_int("BUILD_CAS_MAX_MB", 4096)) * 1024 * 1024,
    "workspaces_max_bytes": max(256, _env_int("BUILD_WORKSPACES_MAX_MB", 4096)) * 1024 * 1024,
    "workspace_ttl": max(300, _env_int("BUILD_WORKSPACE_TTL_SEC", 86400)),
    "min_free_ram_mb": max(0, _env_int("BUILD_MIN_FREE_RAM_MB", 350)),
    "timeout": _env_int("BUILD_TIMEOUT_SEC", 180),
    "memory": os.environ.get("BUILD_MEMORY", "1g"),
    "cpus": os.environ.get("BUILD_CPUS", "1.5"),
    "rate_device": _env_int("BUILD_RATE_PER_DEVICE_HOUR", 60),
    "rate_ip": _env_int("BUILD_RATE_PER_IP_HOUR", 120),
    "data_dir": os.environ.get("BUILD_DATA_DIR", "/var/lib/3012-build"),
    "artifact_ttl": _env_int("BUILD_ARTIFACT_TTL_SEC", 900),
    "runtime": os.environ.get("BUILD_RUNTIME", "").strip(),
    "disk_max_percent": _env_int("BUILD_DISK_MAX_PERCENT", 90),
    "trust_cf_header": os.environ.get("BUILD_TRUST_CF_HEADER", "1") == "1",
    "max_log": 512 * 1024,
    "max_artifact_bytes": 250 * 1024 * 1024,
    "max_sync_total": _env_int("SYNC_MAX_CLIENTS", 128),
    "max_sync_per_ip": _env_int("SYNC_MAX_PER_IP", 12),
    "max_sync_per_room": _env_int("SYNC_MAX_PER_ROOM", 4),
    "max_ws_message": 16 * 1024 * 1024,
}

JOB_ID_RE = re.compile(r"^[a-f0-9]{32}$")
DEVICE_RE = re.compile(r"^[A-Za-z0-9-]{8,64}$")
FILE_RE = re.compile(r"^[A-Za-z0-9._+~-]{1,160}$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
SLUG_RE = re.compile(r"[^A-Za-z0-9._-]+")
ROOM_RE = re.compile(r"^[a-f0-9]{64}$")
CLIENT_ID_RE = re.compile(r"^[A-Za-z0-9._-]{4,64}$")
ALLOWED_EXT = (".deb", ".dylib")
SCHEMES = {"rootless", "rootful", "roothide"}
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
CAS_MAGIC = b"3012CAS1"
CAS_CHUNK_MAX = 8 * 1024 * 1024
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
BLOCKED_ROOT_DIRS = {".git", ".theos", "packages"}


def log(msg: str) -> None:
    sys.stdout.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    sys.stdout.flush()


def short_hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()[:10]


def artifact_dir(job_id: str) -> str:
    return os.path.join(CFG["data_dir"], "artifacts", job_id)


def queue_file(job_id: str) -> str:
    return os.path.join(CFG["data_dir"], "queue", f"{job_id}.zip")


def remove_queue_file(job_id: str) -> None:
    try:
        os.unlink(queue_file(job_id))
    except OSError:
        pass


def stage_dir(job_id: str) -> str:
    return os.path.join(CFG["data_dir"], "stages", job_id)


def workspace_dir(ws_key: str) -> str:
    return os.path.join(CFG["data_dir"], "workspaces", ws_key)


def sanitize_slug(raw: str) -> str:
    cleaned = SLUG_RE.sub("-", (raw or "").strip()).strip("-.")
    return (cleaned[:48] or "project")


def validate_rel_path(raw_path: str):
    if not isinstance(raw_path, str) or "\x00" in raw_path or "\\" in raw_path:
        return None
    if not raw_path or len(raw_path) > 240 or raw_path.startswith("/") or raw_path.endswith("/"):
        return None
    parts = raw_path.split("/")
    if len(parts) > 12:
        return None
    for idx, part in enumerate(parts):
        if not part or part in (".", "..", ".git", ".theos"):
            return None
        if idx == 0 and part in BLOCKED_ROOT_DIRS:
            return None
    return "/".join(parts)


def host_available_ram_mb() -> int:
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("MemAvailable:"):
                    kb = int(line.split()[1])
                    return max(0, kb // 1024)
    except (OSError, ValueError, IndexError):
        pass
    return 4096


def dir_size_bytes(path: str) -> int:
    total = 0
    for root, _dirs, files in os.walk(path, followlinks=False):
        for fname in files:
            fpath = os.path.join(root, fname)
            try:
                if not os.path.islink(fpath):
                    total += os.path.getsize(fpath)
            except OSError:
                pass
    return total


class CASStore:
    def __init__(self):
        self.lock = threading.Lock()
        self.last_used = {}

    def root(self) -> str:
        return os.path.join(CFG["data_dir"], "cas")

    def tmp_dir(self) -> str:
        return os.path.join(self.root(), "tmp")

    def blob_path(self, sha: str) -> str:
        return os.path.join(self.root(), sha[:2], sha)

    def has_blob(self, sha: str) -> bool:
        if sha == EMPTY_SHA256:
            return True
        if not SHA256_RE.match(sha):
            return False
        path = self.blob_path(sha)
        if os.path.isfile(path) and not os.path.islink(path):
            with self.lock:
                self.last_used[sha] = time.time()
            return True
        return False

    def missing_hashes(self, hashes: list) -> list:
        missing = []
        seen = set()
        for sha in hashes:
            if not isinstance(sha, str):
                continue
            low = sha.strip().lower()
            if not SHA256_RE.match(low) or low in seen or low == EMPTY_SHA256:
                continue
            seen.add(low)
            if not self.has_blob(low):
                missing.append(low)
        return missing

    def commit_temp_blob(self, sha: str, tmp_path: str) -> None:
        final_path = self.blob_path(sha)
        os.makedirs(os.path.dirname(final_path), exist_ok=True)
        if os.path.exists(final_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        else:
            try:
                os.chmod(tmp_path, 0o444)
            except OSError:
                pass
            os.replace(tmp_path, final_path)
        with self.lock:
            self.last_used[sha] = time.time()

    def prune(self, protected_hashes=None, target_bytes=None) -> int:
        cas_root = self.root()
        if not os.path.isdir(cas_root):
            return 0
        limit = CFG["cas_max_bytes"] if target_bytes is None else max(0, target_bytes)
        protected = protected_hashes or set()
        entries = []
        total = 0
        with self.lock:
            lu_snapshot = dict(self.last_used)
        for prefix in os.listdir(cas_root):
            if len(prefix) != 2:
                continue
            pdir = os.path.join(cas_root, prefix)
            if not os.path.isdir(pdir):
                continue
            for name in os.listdir(pdir):
                if not SHA256_RE.match(name):
                    continue
                fpath = os.path.join(pdir, name)
                try:
                    st = os.stat(fpath, follow_symlinks=False)
                except OSError:
                    continue
                total += st.st_size
                last_seen = lu_snapshot.get(name, st.st_mtime)
                entries.append((last_seen, st.st_size, name, fpath))
        if total <= limit:
            return 0
        entries.sort(key=lambda item: item[0])
        removed = 0
        for _seen, size, sha, fpath in entries:
            if total <= limit:
                break
            if sha in protected:
                continue
            try:
                os.chmod(fpath, 0o644)
            except OSError:
                pass
            try:
                os.unlink(fpath)
                total -= size
                removed += 1
                with self.lock:
                    self.last_used.pop(sha, None)
            except OSError:
                pass
        return removed


CAS_STORE = CASStore()


# --------------------------------------------------------------------------- Jobs


class Job:
    def __init__(
        self,
        job_id: str,
        device: str,
        ip: str,
        scheme: str,
        payload_path: str = "",
        manifest=None,
        clean_build: bool = False,
        project_slug: str = "project",
    ):
        self.id = job_id
        self.device = device
        self.ip = ip
        self.scheme = scheme
        self.payload_path = payload_path
        self.manifest = manifest
        self.clean_build = clean_build
        self.project_slug = sanitize_slug(project_slug)
        self.workspace_key = hashlib.sha256(
            f"3012-ws-v2:{self.device}:{self.project_slug}:{self.scheme}".encode()
        ).hexdigest()[:24]
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
        if not chunk:
            return
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
            is_active = self.state in ("queued", "running")
        # Avoid splitting a multi-byte UTF-8 sequence across incremental polls.
        if is_active and data:
            trim = 0
            n = len(data)
            tail = min(3, n)
            for k in range(1, tail + 1):
                b = data[n - k]
                if b < 0x80:
                    break
                if (b & 0xC0) == 0xC0:
                    expected = 2 if (b & 0xE0) == 0xC0 else (3 if (b & 0xF0) == 0xE0 else 4)
                    if k < expected:
                        trim = k
                    break
            if trim > 0:
                data = data[: n - trim]
        return data.decode("utf-8", "replace"), offset + len(data)


class BuildQueue:
    def __init__(self):
        self.jobs = {}
        self.pending = deque()
        self.running = set()
        self.active_ws_keys = set()
        self.ws_locks = {}
        self.cond = threading.Condition()
        self.rate = defaultdict(deque)

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

    def allow_upload_batch(self, ip: str) -> bool:
        with self.cond:
            batch_limit = max(240, CFG["rate_ip"] * 8) if CFG["rate_ip"] > 0 else 0
            return self._allow("cas:" + ip, batch_limit)

    def workspace_lock(self, ws_key: str) -> threading.Lock:
        with self.cond:
            lk = self.ws_locks.get(ws_key)
            if lk is None:
                lk = threading.Lock()
                self.ws_locks[ws_key] = lk
            return lk

    def submit(
        self,
        job_id: str,
        device: str,
        ip: str,
        scheme: str,
        payload_path: str = "",
        manifest=None,
        clean_build: bool = False,
        project_slug: str = "project",
    ):
        with self.cond:
            # Anti-spam: cancel any older queued (not yet started) job from the same device
            replaced = [j for j in list(self.pending) if j.device == device]
            for old in replaced:
                self.pending.remove(old)
                old.cancel_requested = True
                old.state = "cancelled"
                old.finished = time.time()
                remove_queue_file(old.id)
            if len(self.pending) >= CFG["max_queue"]:
                return None, ("queue_full", "Máy chủ đang quá tải. Vui lòng thử lại sau hoặc dùng phương thức build khác.")
            if not self._allow("d:" + device, CFG["rate_device"]):
                return None, ("rate_limited", f"Thiết bị đã đạt giới hạn {CFG['rate_device']} lần build/giờ.")
            if not self._allow("i:" + ip, CFG["rate_ip"]):
                return None, ("rate_limited", f"Mạng của bạn đã đạt giới hạn {CFG['rate_ip']} lần build/giờ.")
            job = Job(
                job_id,
                device,
                ip,
                scheme,
                payload_path=payload_path,
                manifest=manifest,
                clean_build=clean_build,
                project_slug=project_slug,
            )
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
            if job.manifest is not None:
                self.active_ws_keys.add(job.workspace_key)
            return job

    def done(self, job: Job) -> None:
        with self.cond:
            self.running.discard(job.id)
            if job.manifest is not None:
                still_queued = any(
                    j.manifest is not None and j.workspace_key == job.workspace_key
                    for j in self.pending
                )
                still_running = any(
                    self.jobs.get(jid) and self.jobs[jid].manifest is not None and self.jobs[jid].workspace_key == job.workspace_key
                    for jid in self.running
                )
                if not still_queued and not still_running:
                    self.active_ws_keys.discard(job.workspace_key)

    def running_count(self) -> int:
        with self.cond:
            return len(self.running)

    def protected_state(self):
        with self.cond:
            active_ws = set(self.active_ws_keys)
            for j in self.pending:
                if j.manifest is not None:
                    active_ws.add(j.workspace_key)
            protected_blobs = set()
            for j in list(self.pending) + [self.jobs[jid] for jid in self.running if jid in self.jobs]:
                if j.manifest:
                    for f in j.manifest.get("files", ()):
                        for sha in f.get("chunks", ()):
                            protected_blobs.add(sha)
            return active_ws, protected_blobs

    def cancel(self, job: Job) -> None:
        should_kill = False
        with self.cond:
            job.cancel_requested = True
            if job in self.pending:
                self.pending.remove(job)
                job.state = "cancelled"
                job.finished = time.time()
                remove_queue_file(job.id)
                return
            if job.state == "running":
                should_kill = True
        if should_kill:
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
            remove_queue_file(job.id)


QUEUE = BuildQueue()


def prune_storage(force: bool = False) -> None:
    active_ws, protected_blobs = QUEUE.protected_state()
    ws_root_base = os.path.join(CFG["data_dir"], "workspaces")
    now = time.time()
    if os.path.isdir(ws_root_base):
        entries = []
        total_ws = 0
        for name in os.listdir(ws_root_base):
            wpath = os.path.join(ws_root_base, name)
            if not os.path.isdir(wpath):
                continue
            marker = os.path.join(wpath, ".last_used")
            try:
                mtime = os.path.getmtime(marker if os.path.exists(marker) else wpath)
            except OSError:
                mtime = now
            sz = dir_size_bytes(wpath)
            total_ws += sz
            entries.append((mtime, sz, name, wpath))
        entries.sort(key=lambda item: item[0])
        limit_ws = CFG["workspaces_max_bytes"] // 2 if force else CFG["workspaces_max_bytes"]
        for mtime, sz, name, wpath in entries:
            if name in active_ws:
                continue
            is_expired = (now - mtime) > CFG["workspace_ttl"]
            if not is_expired and total_ws <= limit_ws:
                continue
            shutil.rmtree(wpath, ignore_errors=True)
            total_ws = max(0, total_ws - sz)

    cas_target = CFG["cas_max_bytes"] // 2 if force else CFG["cas_max_bytes"]
    CAS_STORE.prune(protected_hashes=protected_blobs, target_bytes=cas_target)


# --------------------------------------------------------------------------- Zero-Knowledge WebSocket Sync Relay


class SyncClient:
    def __init__(self, handler, ip: str, client_id: str, role: str, room: str):
        self.handler = handler
        self.ip = ip
        self.client_id = client_id
        self.role = role
        self.room = room
        self.write_lock = threading.Lock()
        self.closed = False
        self.last_seen = time.time()


class SyncRelayHub:
    def __init__(self):
        self.lock = threading.Lock()
        self.rooms = defaultdict(list)  # room -> [SyncClient]
        self.by_ip = defaultdict(int)

    def can_accept_ip(self, ip: str) -> bool:
        with self.lock:
            total = sum(len(peers) for peers in self.rooms.values())
            if total >= CFG["max_sync_total"]:
                return False
            if self.by_ip[ip] >= CFG["max_sync_per_ip"]:
                return False
            return True

    def join(self, client: SyncClient):
        with self.lock:
            peers = self.rooms[client.room]
            same = [p for p in peers if p.client_id == client.client_id]
            for old in same:
                peers.remove(old)
                self.by_ip[old.ip] = max(0, self.by_ip[old.ip] - 1)
                if self.by_ip[old.ip] == 0:
                    del self.by_ip[old.ip]
                old.closed = True
            if len(peers) >= CFG["max_sync_per_room"]:
                return None
            existing = list(peers)
            peers.append(client)
            self.by_ip[client.ip] += 1
            return existing

    def leave(self, client: SyncClient):
        remaining = []
        superseded = False
        with self.lock:
            peers = self.rooms.get(client.room)
            if peers and client in peers:
                peers.remove(client)
                self.by_ip[client.ip] = max(0, self.by_ip[client.ip] - 1)
                if self.by_ip[client.ip] == 0:
                    del self.by_ip[client.ip]
                remaining = list(peers)
                superseded = any(p.client_id == client.client_id for p in remaining)
                if not peers:
                    del self.rooms[client.room]
            elif peers:
                superseded = any(p.client_id == client.client_id for p in peers)
            client.closed = True
        return [] if superseded else remaining

    def peers_for(self, client: SyncClient):
        with self.lock:
            return [p for p in self.rooms.get(client.room, ()) if p is not client and not p.closed]

    def stats(self):
        with self.lock:
            return {
                "syncRooms": len(self.rooms),
                "syncClients": sum(len(v) for v in self.rooms.values()),
            }


SYNC_HUB = SyncRelayHub()


def _ws_read_exact(rfile, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = rfile.read(n - len(buf))
        if not chunk:
            raise EOFError("WebSocket EOF")
        buf.extend(chunk)
    return bytes(buf)


def _ws_send_frame(client: SyncClient, opcode: int, payload: bytes = b"") -> bool:
    if client.closed:
        return False
    length = len(payload)
    if length < 126:
        header = bytes([0x80 | (opcode & 0x0F), length])
    elif length < 65536:
        header = struct.pack("!BBH", 0x80 | (opcode & 0x0F), 126, length)
    else:
        header = struct.pack("!BBQ", 0x80 | (opcode & 0x0F), 127, length)
    try:
        with client.write_lock:
            if client.closed:
                return False
            client.handler.wfile.write(header + payload)
            client.handler.wfile.flush()
        return True
    except OSError:
        client.closed = True
        return False


def _ws_send_json(client: SyncClient, obj: dict) -> bool:
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return _ws_send_frame(client, 0x1, data)


def _ws_read_message(handler, client: SyncClient):
    """Read one full RFC 6455 data message from handler.rfile, handling fragmentation & control frames."""
    rfile = handler.rfile
    fragments = bytearray()
    collecting = False
    msg_opcode = 0x1

    while True:
        b1, b2 = _ws_read_exact(rfile, 2)
        fin = (b1 & 0x80) != 0
        opcode = b1 & 0x0F
        masked = (b2 & 0x80) != 0
        length = b2 & 0x7F

        if not masked:
            # RFC 6455 section 5.1: client->server frames MUST be masked
            _ws_send_frame(client, 0x8, struct.pack("!H", 1002))
            return None

        if length == 126:
            (length,) = struct.unpack("!H", _ws_read_exact(rfile, 2))
        elif length == 127:
            (length,) = struct.unpack("!Q", _ws_read_exact(rfile, 8))

        if length > CFG["max_ws_message"]:
            _ws_send_frame(client, 0x8, struct.pack("!H", 1009))
            return None

        mask_key = _ws_read_exact(rfile, 4)
        payload = bytearray(_ws_read_exact(rfile, length))
        if payload:
            m0, m1, m2, m3 = mask_key
            for i in range(len(payload)):
                r = i & 3
                payload[i] ^= m0 if r == 0 else (m1 if r == 1 else (m2 if r == 2 else m3))
        raw = bytes(payload)
        client.last_seen = time.time()

        # Control frames (may appear in between fragments)
        if opcode == 0x8:
            _ws_send_frame(client, 0x8, raw[:2] if len(raw) >= 2 else struct.pack("!H", 1000))
            return None
        if opcode == 0x9:
            _ws_send_frame(client, 0xA, raw[:125])
            continue
        if opcode == 0xA:
            continue

        if opcode in (0x1, 0x2):
            if collecting:
                _ws_send_frame(client, 0x8, struct.pack("!H", 1002))
                return None
            msg_opcode = opcode
            fragments = bytearray(raw)
            if fin:
                return msg_opcode, bytes(fragments)
            collecting = True
        elif opcode == 0x0:
            if not collecting:
                _ws_send_frame(client, 0x8, struct.pack("!H", 1002))
                return None
            if len(fragments) + len(raw) > CFG["max_ws_message"]:
                _ws_send_frame(client, 0x8, struct.pack("!H", 1009))
                return None
            fragments.extend(raw)
            if fin:
                return msg_opcode, bytes(fragments)
        else:
            _ws_send_frame(client, 0x8, struct.pack("!H", 1002))
            return None


# --------------------------------------------------------------------------- Worker


def safe_src_join(src_root: str, rel_path: str) -> str:
    base = os.path.abspath(src_root)
    joined = os.path.abspath(os.path.join(base, *rel_path.split("/")))
    if not joined.startswith(base + os.sep):
        raise ValueError("Path escapes workspace src root")
    return joined


def _container_ids():
    euid = getattr(os, "getuid", lambda: 1000)()
    egid = getattr(os, "getgid", lambda: 1000)()
    if euid == 0:
        return 1000, 1000, True
    return euid, egid, False


def _chown_tree(path: str, uid: int, gid: int) -> None:
    chown_fn = getattr(os, "chown", None)
    if chown_fn is None:
        return
    try:
        chown_fn(path, uid, gid)
    except OSError:
        return
    for root, dirs, files in os.walk(path, followlinks=False):
        for d in dirs:
            try:
                chown_fn(os.path.join(root, d), uid, gid)
            except OSError:
                pass
        for f in files:
            try:
                chown_fn(os.path.join(root, f), uid, gid)
            except OSError:
                pass


def prepare_incremental_workspace(job: Job):
    ws_root = os.path.abspath(workspace_dir(job.workspace_key))
    src_root = os.path.join(ws_root, "src")
    out_dir = os.path.join(ws_root, "out")
    home_dir = os.path.join(ws_root, "home")
    stg_root = os.path.abspath(stage_dir(job.id))
    os.makedirs(ws_root, exist_ok=True)
    os.makedirs(src_root, exist_ok=True)
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(home_dir, exist_ok=True)
    os.makedirs(stg_root, exist_ok=True)

    # Touch LRU marker
    marker = os.path.join(ws_root, ".last_used")
    with open(marker, "wb"):
        pass
    try:
        os.utime(marker, None)
    except OSError:
        pass

    manifest_file = os.path.join(ws_root, ".3012-manifest.json")
    prev_files = {}
    try:
        with open(manifest_file, "r", encoding="utf-8") as fh:
            loaded = json.load(fh)
            if isinstance(loaded, dict):
                prev_files = loaded
    except (OSError, json.JSONDecodeError):
        prev_files = {}

    entries = job.manifest.get("files", [])
    new_paths = {f["path"] for f in entries}

    # Remove files deleted since last build and clean empty parent dirs
    for old_rel in list(prev_files.keys()):
        if old_rel not in new_paths:
            try:
                old_abs = safe_src_join(src_root, old_rel)
                if os.path.isdir(old_abs) and not os.path.islink(old_abs):
                    shutil.rmtree(old_abs, ignore_errors=True)
                elif os.path.lexists(old_abs):
                    os.unlink(old_abs)
                cur = os.path.dirname(old_abs)
                src_abs = os.path.abspath(src_root)
                while cur != src_abs and cur.startswith(src_abs + os.sep):
                    try:
                        os.rmdir(cur)
                        cur = os.path.dirname(cur)
                    except OSError:
                        break
            except (ValueError, OSError):
                pass

    new_meta_map = {}
    updated_count = 0
    kept_count = 0
    sync_tmp = os.path.join(ws_root, ".sync_tmp")

    for entry in entries:
        rel = entry["path"]
        size = entry["size"]
        chunks = entry["chunks"]
        is_exec = bool(entry.get("exec", False))
        meta = {"size": size, "chunks": chunks, "exec": is_exec}
        new_meta_map[rel] = meta

        dst = safe_src_join(src_root, rel)
        prev_meta = prev_files.get(rel)
        if (
            prev_meta == meta
            and os.path.isfile(dst)
            and not os.path.islink(dst)
            and os.path.getsize(dst) == size
        ):
            kept_count += 1
            continue

        parent = os.path.dirname(dst)
        # Ensure no regular file/symlink blocks parent directory creation
        rel_parts = rel.split("/")[:-1]
        walk_dir = src_root
        for part in rel_parts:
            walk_dir = os.path.join(walk_dir, part)
            if os.path.lexists(walk_dir) and not os.path.isdir(walk_dir):
                os.unlink(walk_dir)
        os.makedirs(parent, exist_ok=True)
        if os.path.isdir(dst) and not os.path.islink(dst):
            shutil.rmtree(dst, ignore_errors=True)

        with open(sync_tmp, "wb") as out_fh:
            if size > 0 and chunks:
                for sha in chunks:
                    bpath = CAS_STORE.blob_path(sha)
                    with open(bpath, "rb") as in_fh:
                        shutil.copyfileobj(in_fh, out_fh, length=65536)
        try:
            os.chmod(sync_tmp, 0o755 if is_exec else 0o644)
        except OSError:
            pass
        os.replace(sync_tmp, dst)
        updated_count += 1

    tmp_manifest = manifest_file + ".tmp"
    with open(tmp_manifest, "w", encoding="utf-8") as fh:
        json.dump(new_meta_map, fh, separators=(",", ":"))
    os.replace(tmp_manifest, manifest_file)

    uid, gid, need_chown = _container_ids()
    if need_chown:
        _chown_tree(ws_root, uid, gid)

    passwd_file = None
    if uid != 1000:
        passwd_file = os.path.join(stg_root, "passwd")
        with open(passwd_file, "w", encoding="utf-8") as fh:
            fh.write(
                "root:x:0:0:root:/root:/bin/bash\n"
                f"builder:x:{uid}:{gid}:builder:/work/home:/bin/bash\n"
                "nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin\n"
            )
        try:
            os.chmod(passwd_file, 0o644)
        except OSError:
            pass

    return ws_root, stg_root, uid, gid, passwd_file, updated_count, len(entries)


def docker_command(job: Job, ws_root=None, uid: int = 1000, gid: int = 1000, passwd_file=None, make_jobs: int = 2):
    cmd = [
        "docker", "run", "--rm", "-i",
        "--name", job.container_name,
        "--hostname", "builder",
        "--network", "none",
        "--read-only",
    ]
    if ws_root is not None:
        cmd += [
            "-v", f"{ws_root}:/work:rw",
            "--tmpfs", f"/tmp:rw,exec,nosuid,nodev,size=256m,uid={uid},gid={gid},mode=1777",
            "--user", f"{uid}:{gid}",
            "-e", "BUILD_MODE=incremental",
            "-e", "CLEAN_BUILD=" + ("1" if job.clean_build else "0"),
        ]
        if passwd_file:
            cmd += ["-v", f"{passwd_file}:/etc/passwd:ro"]
    else:
        cmd += [
            "--tmpfs", "/work:rw,exec,nosuid,nodev,size=768m,uid=1000,gid=1000,mode=0700",
            "--tmpfs", "/tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000,mode=1777",
            "--user", "1000:1000",
            "-e", "BUILD_MODE=zip",
        ]
    cmd += [
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--pids-limit", "256",
        "--memory", CFG["memory"],
        "--memory-swap", CFG["memory"],
        "--cpus", CFG["cpus"],
        "--cpu-shares", "256",
        "--oom-score-adj", "500",
        "--ulimit", "nofile=1024:1024",
        "--ulimit", "fsize=268435456:268435456",
        "--log-driver", "none",
        "-e", "USER=builder",
        "-e", "LOGNAME=builder",
        "-e", f"MAKE_JOBS={make_jobs}",
        "-e", "PACKAGE_SCHEME=" + job.scheme,
    ]
    if CFG["runtime"]:
        cmd += ["--runtime", CFG["runtime"]]
    cmd.append(CFG["image"])
    return cmd


def extract_artifacts_stream(job: Job, stream):
    target = artifact_dir(job.id)
    os.makedirs(target, exist_ok=True)
    files = []
    total_written = 0
    try:
        with tarfile.open(fileobj=stream, mode="r|") as tar:
            for member in tar:
                if not member.isfile():
                    continue
                name = os.path.basename(member.name)
                if not FILE_RE.match(name) or not name.endswith(ALLOWED_EXT):
                    continue
                if member.size < 0 or member.size > CFG["max_artifact_bytes"] or total_written + member.size > CFG["max_artifact_bytes"]:
                    continue
                src = tar.extractfile(member)
                if src is None:
                    continue
                path = os.path.join(target, name)
                written = 0
                oversize = False
                with open(path, "wb") as dst:
                    while True:
                        chunk = src.read(65536)
                        if not chunk:
                            break
                        written += len(chunk)
                        if written > CFG["max_artifact_bytes"] or total_written + written > CFG["max_artifact_bytes"]:
                            oversize = True
                            break
                        dst.write(chunk)
                if oversize:
                    try:
                        os.unlink(path)
                    except OSError:
                        pass
                    continue
                total_written += written
                files.append({"name": name, "size": written})
    except (tarfile.TarError, EOFError, OSError):
        pass
    return files


def run_job(job: Job) -> None:
    job.state = "running"
    job.started = time.time()

    # Host RAM admission guard to prevent OOM when running concurrent builds
    waited = 0
    while (
        not job.cancel_requested
        and waited < 20
        and CFG["min_free_ram_mb"] > 0
        and QUEUE.running_count() > 1
        and host_available_ram_mb() < CFG["min_free_ram_mb"]
    ):
        if waited == 0:
            job.append_log(b"[3012] May chu dang ban - cho RAM trong de chong qua tai...\n")
        time.sleep(2)
        waited += 1

    if job.cancel_requested:
        job.state = "cancelled"
        job.finished = time.time()
        remove_queue_file(job.id)
        return

    avail_ram = host_available_ram_mb()
    make_jobs = 1 if avail_ram < 450 else 2

    is_cas = job.manifest is not None
    ws_lock = QUEUE.workspace_lock(job.workspace_key) if is_cas else None
    stg_root = None

    try:
        if ws_lock is not None:
            ws_lock.acquire()
            ws_root, stg_root, uid, gid, passwd_file, updated_cnt, total_cnt = prepare_incremental_workspace(job)
            job.append_log(
                f"[3012] Bắt đầu CAS delta build ({job.project_slug} • {job.scheme} • cập nhật {updated_cnt}/{total_cnt} file, giới hạn {CFG['timeout']}s).\n".encode()
            )
            dcmd = docker_command(
                job,
                ws_root=ws_root,
                uid=uid,
                gid=gid,
                passwd_file=passwd_file,
                make_jobs=make_jobs,
            )
        else:
            job.append_log(
                f"[3012] Bắt đầu build (scheme: {job.scheme}, giới hạn {CFG['timeout']}s, RAM {CFG['memory']}).\n".encode()
            )
            dcmd = docker_command(job, make_jobs=make_jobs)

        proc = subprocess.Popen(
            dcmd,
            stdin=subprocess.PIPE if not is_cas else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        def feed():
            try:
                with open(job.payload_path, "rb") as src:
                    while True:
                        chunk = src.read(65536)
                        if not chunk:
                            break
                        proc.stdin.write(chunk)
            except (BrokenPipeError, OSError):
                pass
            finally:
                try:
                    if proc.stdin:
                        proc.stdin.close()
                except OSError:
                    pass
                remove_queue_file(job.id)

        def pump_log():
            try:
                while True:
                    chunk = proc.stderr.read(8192)
                    if not chunk:
                        break
                    job.append_log(chunk)
            except OSError:
                pass

        extracted_files = []

        def pump_out():
            nonlocal extracted_files
            try:
                extracted_files = extract_artifacts_stream(job, proc.stdout)
                while proc.stdout.read(65536):
                    pass
            except OSError:
                pass

        threads = [
            threading.Thread(target=pump_log, daemon=True),
            threading.Thread(target=pump_out, daemon=True),
        ]
        if not is_cas:
            threads.append(threading.Thread(target=feed, daemon=True))
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

        remove_queue_file(job.id)
        job.exit_code = proc.returncode
        files = extracted_files
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
    finally:
        if ws_lock is not None:
            ws_lock.release()
        if stg_root:
            shutil.rmtree(stg_root, ignore_errors=True)
        job.finished = time.time()
        log(
            f"job={job.id[:8]} device={short_hash(job.device)} mode={'cas' if is_cas else 'zip'} "
            f"state={job.state} exit={job.exit_code} secs={(job.finished - job.started):.1f}"
        )


def worker_loop() -> None:
    while True:
        job = QUEUE.next_job()
        try:
            if job.cancel_requested:
                job.state = "cancelled"
                job.finished = time.time()
                remove_queue_file(job.id)
                continue
            run_job(job)
        except Exception as exc:  # never let a worker die
            job.state = "failed"
            job.error = "internal_error"
            job.finished = time.time()
            remove_queue_file(job.id)
            job.append_log(f"\n[3012] Lỗi nội bộ máy chủ: {type(exc).__name__}\n".encode())
            log(f"job={job.id[:8]} internal error: {exc!r}")
        finally:
            QUEUE.done(job)


def janitor_loop() -> None:
    while True:
        time.sleep(60)
        try:
            QUEUE.cleanup()
            prune_storage(force=False)
        except Exception as exc:
            log(f"janitor error: {exc!r}")


# --------------------------------------------------------------------------- Companion /sync.mjs Script Template

SYNC_MJS_TEMPLATE = r"""#!/usr/bin/env node
// 3012 PC Sync Companion v5.1 (Zero npm dependencies! Requires Node.js 18+)
// Chay trong thu muc code tren PC: node sync.mjs [--key=<KEY>] [--pin=<6SO>] [--dir=<PATH>]
import http from "node:http";
import net from "node:net";
import tls from "node:tls";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";
import { spawn } from "node:child_process";

const args = process.argv.slice(2);
function getArg(name) {
  const eq = args.find((a) => a.startsWith(`--${name}=`));
  if (eq) return eq.slice(name.length + 3);
  const idx = args.indexOf(`--${name}`);
  if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
  return "";
}

const DEFAULT_RELAY = "__DEFAULT_RELAY__";
const RELAY_URL = (getArg("relay") || process.env.SYNC_RELAY || DEFAULT_RELAY).trim();
const PORT = Number(getArg("port") || args.find((a) => /^\d+$/.test(a)) || process.env.SYNC_PORT || 30120);
const LAN_ONLY = args.includes("--lan-only");
const ROOT = path.resolve(getArg("dir") || process.cwd());
const CONFIG_FILE = path.join(os.homedir(), ".3012-sync.json");
const CLIENT_ID = "pc-" + crypto.randomBytes(6).toString("hex");
const IGNORED = new Set([".git", "node_modules", ".next", "dist", "build", ".DS_Store", "__pycache__", ".venv", ".build"]);
const MAX_WS_MESSAGE = 16 * 1024 * 1024;

function loadStoredKey() {
  try {
    const raw = fs.readFileSync(CONFIG_FILE, "utf8");
    const j = JSON.parse(raw);
    return typeof j.permanentKey === "string" ? j.permanentKey.trim() : "";
  } catch {
    return "";
  }
}

function saveStoredKey(k) {
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify({ permanentKey: k, updatedAt: new Date().toISOString() }, null, 2), { encoding: "utf8", mode: 0o600 });
  } catch {}
}

function randomPermanentKey() {
  return "k3012_" + crypto.randomBytes(12).toString("base64url");
}

function randomPin6() {
  return String(crypto.randomInt(100000, 1000000));
}

let PERMANENT_KEY = (getArg("key") || getArg("token") || process.env.SYNC_KEY || process.env.SYNC_TOKEN || "").trim();
let QUICK_PIN = (getArg("pin") || "").trim();
if (!PERMANENT_KEY && !QUICK_PIN) {
  PERMANENT_KEY = loadStoredKey();
  if (!PERMANENT_KEY) {
    PERMANENT_KEY = randomPermanentKey();
    saveStoredKey(PERMANENT_KEY);
    QUICK_PIN = randomPin6();
  }
} else if (PERMANENT_KEY) {
  saveStoredKey(PERMANENT_KEY);
} else if (QUICK_PIN) {
  PERMANENT_KEY = loadStoredKey() || randomPermanentKey();
  saveStoredKey(PERMANENT_KEY);
}

const ACTIVE_PAIRING_SECRET = QUICK_PIN || PERMANENT_KEY;
let issuedKeyOnPair = Boolean(QUICK_PIN);

function deriveRoomID(secret) {
  return crypto.createHash("sha256").update("3012-room-v1:" + String(secret || "").trim(), "utf8").digest("hex");
}

function deriveAESKey(secret) {
  return crypto.createHash("sha256").update("3012-e2ee-v1:" + String(secret || "").trim(), "utf8").digest();
}

function encryptE2EE(obj, key32) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key32, iv);
  const pt = Buffer.from(JSON.stringify(obj), "utf8");
  const ct = Buffer.concat([cipher.update(pt), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, ct, tag]).toString("base64");
}

function decryptE2EE(b64, key32) {
  const buf = Buffer.from(String(b64 || ""), "base64");
  if (buf.length < 28) return null;
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(buf.length - 16);
  const ct = buf.subarray(12, buf.length - 16);
  const decipher = crypto.createDecipheriv("aes-256-gcm", key32, iv);
  decipher.setAuthTag(tag);
  const pt = Buffer.concat([decipher.update(ct), decipher.final()]);
  return JSON.parse(pt.toString("utf8"));
}

function getLanIP() {
  const nets = os.networkInterfaces();
  for (const list of Object.values(nets)) {
    for (const info of list || []) {
      if (info.family === "IPv4" && !info.internal) return info.address;
    }
  }
  return "127.0.0.1";
}

function safeResolve(relPath) {
  const clean = String(relPath || "").replace(/\\/g, "/").replace(/^\/+/, "");
  if (!clean || clean === "." || clean.split("/").some((s) => s === ".." || s === "")) return null;
  const abs = path.resolve(ROOT, clean);
  if (abs !== ROOT && !abs.startsWith(ROOT + path.sep)) return null;
  try {
    let probe = abs;
    while (probe !== ROOT && !fs.existsSync(probe)) {
      probe = path.dirname(probe);
    }
    const realProbe = fs.realpathSync(probe);
    const realRoot = fs.realpathSync(ROOT);
    if (realProbe !== realRoot && !realProbe.startsWith(realRoot + path.sep)) return null;
  } catch {
    return null;
  }
  return abs;
}

function isTextBuffer(buf) {
  const sample = buf.subarray(0, Math.min(buf.length, 4096));
  for (let i = 0; i < sample.length; i++) {
    if (sample[i] === 0) return false;
  }
  return true;
}

function collectSnapshot(dir = ROOT, base = "", out = {}) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const entry of entries) {
    if (IGNORED.has(entry.name) || entry.name.startsWith(".3012")) continue;
    if (entry.isSymbolicLink()) continue;
    const rel = base ? `${base}/${entry.name}` : entry.name;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectSnapshot(full, rel, out);
    } else if (entry.isFile()) {
      try {
        const st = fs.lstatSync(full);
        if (st.isSymbolicLink() || !st.isFile() || st.size > 512 * 1024) continue;
        const buf = fs.readFileSync(full);
        if (isTextBuffer(buf)) out[rel] = buf.toString("utf8");
      } catch {}
    }
  }
  return out;
}

const suppressedPaths = new Map();
function suppressEcho(rel) { suppressedPaths.set(rel, Date.now() + 900); }
function isSuppressed(rel) {
  const exp = suppressedPaths.get(rel);
  if (!exp) return false;
  if (Date.now() > exp) { suppressedPaths.delete(rel); return false; }
  return true;
}

function encodeWsFrame(opcode, payloadBuf, masked) {
  const len = payloadBuf.length;
  const maskBit = masked ? 0x80 : 0x00;
  let header;
  if (len < 126) {
    header = Buffer.from([0x80 | opcode, maskBit | len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode; header[1] = maskBit | 126; header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode; header[1] = maskBit | 127; header.writeBigUInt64BE(BigInt(len), 2);
  }
  if (!masked) return Buffer.concat([header, payloadBuf]);
  const mask = crypto.randomBytes(4);
  const body = Buffer.allocUnsafe(len);
  for (let i = 0; i < len; i++) body[i] = payloadBuf[i] ^ mask[i & 3];
  return Buffer.concat([header, mask, body]);
}

function attachWsDecoder(socket, onMessage, onClose) {
  let buf = Buffer.alloc(0);
  let collecting = false;
  let frags = [];
  let fragLen = 0;

  socket.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    while (buf.length >= 2) {
      const b1 = buf[0], b2 = buf[1];
      const fin = (b1 & 0x80) !== 0;
      const opcode = b1 & 0x0f;
      const masked = (b2 & 0x80) !== 0;
      let payloadLen = b2 & 0x7f;
      let offset = 2;
      if (payloadLen === 126) {
        if (buf.length < 4) return;
        payloadLen = buf.readUInt16BE(2); offset = 4;
      } else if (payloadLen === 127) {
        if (buf.length < 10) return;
        payloadLen = Number(buf.readBigUInt64BE(2)); offset = 10;
      }
      if (payloadLen > MAX_WS_MESSAGE) { socket.destroy(); return; }
      const maskSize = masked ? 4 : 0;
      if (buf.length < offset + maskSize + payloadLen) return;
      const mask = masked ? buf.subarray(offset, offset + 4) : null;
      let payload = buf.subarray(offset + maskSize, offset + maskSize + payloadLen);
      buf = buf.subarray(offset + maskSize + payloadLen);
      if (mask) {
        const dec = Buffer.allocUnsafe(payload.length);
        for (let i = 0; i < payload.length; i++) dec[i] = payload[i] ^ mask[i & 3];
        payload = dec;
      }
      if (opcode === 0x8) { socket.end(); return; }
      if (opcode === 0x9) {
        try { socket.write(encodeWsFrame(0xA, payload.subarray(0, 125), false)); } catch {}
        continue;
      }
      if (opcode === 0xA) continue;
      if (opcode === 0x1 || opcode === 0x2) {
        frags = [payload];
        fragLen = payload.length;
        collecting = !fin;
        if (fin) onMessage(Buffer.concat(frags));
      } else if (opcode === 0x0 && collecting) {
        fragLen += payload.length;
        if (fragLen > MAX_WS_MESSAGE) { socket.destroy(); return; }
        frags.push(payload);
        if (fin) { collecting = false; onMessage(Buffer.concat(frags)); }
      }
    }
  });
  socket.on("close", onClose);
  socket.on("error", onClose);
}

const lanClients = new Set();
let relayConns = [];

function handleProtocolMessage(msg, replyFn, broadcastFn) {
  if (!msg || typeof msg !== "object") return;
  if (msg.type === "ping") {
    replyFn({ type: "pong", ts: msg.ts });
  } else if (msg.type === "request_snapshot") {
    replyFn({ type: "snapshot", files: collectSnapshot() });
  } else if (msg.type === "push_snapshot" && msg.files && typeof msg.files === "object") {
    for (const [rel, body] of Object.entries(msg.files)) {
      const abs = safeResolve(rel);
      if (!abs || typeof body !== "string") continue;
      suppressEcho(rel);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, body, "utf8");
    }
  } else if (msg.type === "upsert" && typeof msg.path === "string" && typeof msg.content === "string") {
    const abs = safeResolve(msg.path);
    if (abs) {
      suppressEcho(msg.path);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, msg.content, "utf8");
      broadcastFn(msg);
      console.log("[<- Mobile]", msg.path);
    }
  } else if (msg.type === "delete" && typeof msg.path === "string") {
    const abs = safeResolve(msg.path);
    if (abs && fs.existsSync(abs)) {
      suppressEcho(msg.path);
      fs.rmSync(abs, { recursive: true, force: true });
      broadcastFn(msg);
      console.log("[<- Mobile DELETE]", msg.path);
    }
  } else if (msg.type === "rename" && msg.oldPath && msg.path) {
    const src = safeResolve(msg.oldPath);
    const dst = safeResolve(msg.path);
    if (src && dst && fs.existsSync(src)) {
      suppressEcho(msg.oldPath);
      suppressEcho(msg.path);
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.renameSync(src, dst);
      broadcastFn(msg);
    }
  } else if (msg.type === "mkdir" && msg.path) {
    const abs = safeResolve(msg.path);
    if (abs) {
      fs.mkdirSync(abs, { recursive: true });
      broadcastFn(msg);
    }
  } else if (msg.type === "exec_cmd" && msg.command) {
    const child = spawn(msg.command, { cwd: ROOT, shell: true });
    let stdout = "", stderr = "";
    const MAX_OUT = 1024 * 1024;
    const timer = setTimeout(() => { try { child.kill("SIGTERM"); } catch {} }, 30000);
    child.stdout.on("data", (d) => { if (stdout.length < MAX_OUT) stdout += d.toString("utf8"); });
    child.stderr.on("data", (d) => { if (stderr.length < MAX_OUT) stderr += d.toString("utf8"); });
    child.on("close", (code) => {
      clearTimeout(timer);
      replyFn({ type: "cmd_result", id: msg.id || "", exitCode: code ?? 0, stdout, stderr });
    });
  }
}

function broadcastEverywhere(obj, exceptLan = null) {
  const lanFrame = encodeWsFrame(0x1, Buffer.from(JSON.stringify(obj), "utf8"), false);
  for (const c of lanClients) {
    if (c !== exceptLan && c.authenticated && !c.socket.destroyed) {
      try { c.socket.write(lanFrame); } catch {}
    }
  }
  for (const rc of relayConns) {
    if (rc.ready && !rc.socket.destroyed) {
      rc.sendApp(obj);
    }
  }
}

// Local Wi-Fi LAN Server (30120)
const lanServer = http.createServer((_req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
  res.end(`3012 PC Sync Companion running in ${ROOT}\n`);
});

lanServer.on("upgrade", (req, socket) => {
  const key = req.headers["sec-websocket-key"];
  if (!key) { socket.destroy(); return; }
  const accept = crypto.createHash("sha1").update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  socket.write([
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${accept}`,
    "\r\n"
  ].join("\r\n"));

  const client = { socket, authenticated: false };
  lanClients.add(client);
  const replyFn = (o) => {
    if (!socket.destroyed) socket.write(encodeWsFrame(0x1, Buffer.from(JSON.stringify(o), "utf8"), false));
  };

  attachWsDecoder(socket, (rawBuf) => {
    let msg;
    try { msg = JSON.parse(rawBuf.toString("utf8")); } catch { return; }
    if (!client.authenticated) {
      if (msg.type === "hello" && (msg.token === PERMANENT_KEY || msg.token === ACTIVE_PAIRING_SECRET)) {
        client.authenticated = true;
        replyFn({
          type: "welcome",
          projectName: path.basename(ROOT),
          rootDir: ROOT,
          lanUrl: `ws://${getLanIP()}:${PORT}`,
          issuedPermanentKey: issuedKeyOnPair ? PERMANENT_KEY : undefined
        });
      } else {
        replyFn({ type: "error", message: "Sai Khoa Dong Bo" });
        socket.end();
      }
      return;
    }
    handleProtocolMessage(msg, replyFn, (o) => broadcastEverywhere(o, client));
  }, () => lanClients.delete(client));
});

// Outbound Relay Connector (Zero-Knowledge AES-256-GCM via build.kaydus.xyz)
function connectRelayRoom(secret, isPinRoom = false) {
  if (LAN_ONLY || !RELAY_URL) return null;
  const u = new URL(RELAY_URL);
  const isTLS = u.protocol === "wss:" || u.protocol === "https:";
  const port = Number(u.port || (isTLS ? 443 : 80));
  const pathWithQuery = (u.pathname || "/v1/sync") + (u.search || "");
  const room = deriveRoomID(secret);
  const aesKey = deriveAESKey(secret);
  const rc = { socket: null, ready: false, closed: false, sendApp: () => {}, close: () => { rc.closed = true; rc.ready = false; try { rc.socket && rc.socket.destroy(); } catch {} } };

  function connectOnce() {
    if (rc.closed) return;
    const sock = isTLS
      ? tls.connect({ host: u.hostname, port, servername: u.hostname })
      : net.connect({ host: u.hostname, port });
    rc.socket = sock;
    rc.ready = false;

    const wsKey = crypto.randomBytes(16).toString("base64");
    let upgraded = false;
    let headerBuf = Buffer.alloc(0);

    function sendRawJSON(obj) {
      if (sock.destroyed) return;
      sock.write(encodeWsFrame(0x1, Buffer.from(JSON.stringify(obj), "utf8"), true));
    }
    rc.sendApp = (obj) => {
      sendRawJSON({ type: "relay_packet", p: encryptE2EE(obj, aesKey) });
    };

    const pingInterval = setInterval(() => {
      if (!sock.destroyed && upgraded) {
        try { sock.write(encodeWsFrame(0x9, Buffer.from("3012"), true)); } catch {}
      }
    }, 25000);

    sock.on("connect", () => {
      const req = [
        `GET ${pathWithQuery} HTTP/1.1`,
        `Host: ${u.host}`,
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Key: ${wsKey}`,
        "Sec-WebSocket-Version: 13",
        "User-Agent: 3012-Sync-Companion/5.1",
        "\r\n"
      ].join("\r\n");
      sock.write(req);
    });

    function onRelayData(chunk) {
      if (upgraded) return;
      headerBuf = Buffer.concat([headerBuf, chunk]);
      const idx = headerBuf.indexOf("\r\n\r\n");
      if (idx < 0) return;
      const head = headerBuf.subarray(0, idx).toString("latin1");
      const leftover = headerBuf.subarray(idx + 4);
      sock.removeListener("data", onRelayData);
      if (!/^HTTP\/1\.[01]\s+101\b/i.test(head)) {
        sock.destroy();
        return;
      }
      upgraded = true;
      rc.ready = true;
      sendRawJSON({ type: "relay_join", room, role: "pc", clientId: CLIENT_ID });

      attachWsDecoder(sock, (buf) => {
        let env;
        try { env = JSON.parse(buf.toString("utf8")); } catch { return; }
        if (env.type === "relay_packet" && typeof env.p === "string") {
          let msg = null;
          try { msg = decryptE2EE(env.p, aesKey); } catch { return; }
          if (!msg) return;
          if (msg.type === "hello") {
            rc.sendApp({
              type: "welcome",
              projectName: path.basename(ROOT),
              rootDir: ROOT,
              lanUrl: `ws://${getLanIP()}:${PORT}`,
              lanToken: PERMANENT_KEY,
              issuedPermanentKey: issuedKeyOnPair ? PERMANENT_KEY : undefined
            });
            console.log("[3012 Relay] Dien thoai da ghep noi E2EE thanh cong!");
            if (isPinRoom) setTimeout(() => rc.close(), 1500);
            return;
          }
          handleProtocolMessage(msg, rc.sendApp, (o) => broadcastEverywhere(o));
        } else if (env.type === "relay_peer_joined") {
          console.log(`[3012 Relay] Thiet bi '${env.role || "mobile"}' da vao phong dong bo.`);
        }
      }, () => {
        clearInterval(pingInterval);
        rc.ready = false;
      });
      if (leftover.length > 0) sock.emit("data", leftover);
    }

    sock.on("data", onRelayData);
    sock.on("close", () => {
      clearInterval(pingInterval);
      rc.ready = false;
      if (!rc.closed) setTimeout(connectOnce, 3500);
    });
    sock.on("error", () => {});
  }

  connectOnce();
  return rc;
}

try {
  fs.watch(ROOT, { recursive: true }, (_event, filename) => {
    if (!filename) return;
    const rel = String(filename).split(path.sep).join("/");
    if (rel.split("/").some((p) => IGNORED.has(p) || p.startsWith(".3012"))) return;
    if (isSuppressed(rel)) return;
    const abs = safeResolve(rel);
    if (!abs) return;
    setTimeout(() => {
      try {
        if (!fs.existsSync(abs)) {
          broadcastEverywhere({ type: "delete", path: rel, isDir: false });
        } else {
          const st = fs.lstatSync(abs);
          if (!st.isSymbolicLink() && st.isFile() && st.size <= 512 * 1024) {
            const buf = fs.readFileSync(abs);
            if (isTextBuffer(buf)) broadcastEverywhere({ type: "upsert", path: rel, content: buf.toString("utf8") });
          }
        }
      } catch {}
    }, 90);
  });
} catch (err) {
  console.warn("[3012] Recursive fs.watch khong kha dung:", err.message);
}

lanServer.listen(PORT, "0.0.0.0", () => {
  const lanUrl = `ws://${getLanIP()}:${PORT}`;
  console.log("\n====================================================");
  console.log("  3012 PC SYNC v5.1 (E2EE AES-256-GCM + 4G/Wi-Fi)  ");
  console.log("====================================================");
  console.log("Project      :", ROOT);
  console.log("Relay Server :", RELAY_URL);
  console.log("Wi-Fi LAN    :", lanUrl);
  if (QUICK_PIN) console.log("PIN 6 So     :", QUICK_PIN);
  console.log("Khoa Vinh Vien:", PERMANENT_KEY);
  console.log("====================================================\n");

  const r1 = connectRelayRoom(PERMANENT_KEY, false);
  if (r1) relayConns.push(r1);
  if (QUICK_PIN && QUICK_PIN !== PERMANENT_KEY) {
    const rPin = connectRelayRoom(QUICK_PIN, true);
    if (rPin) {
      relayConns.push(rPin);
      setTimeout(() => rPin.close(), 180000);
    }
  }
});
"""


# --------------------------------------------------------------------------- HTTP & WebSocket API


def disk_usage_percent() -> int:
    usage = shutil.disk_usage(CFG["data_dir"])
    return int(usage.used * 100 / usage.total)


class Handler(BaseHTTPRequestHandler):
    server_version = "3012-build/" + VERSION
    sys_version = ""
    protocol_version = "HTTP/1.1"
    timeout = 65

    def log_message(self, fmt, *args):  # quiet: no IPs or payloads in logs
        pass

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
        if self.close_connection:
            self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def send_text(self, status: int, body: str, content_type: str) -> None:
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
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
            "elapsed": 0.0 if not job.started else round(max(0.0, (job.finished or time.time()) - job.started), 1),
        }

    def handle_sync_websocket(self) -> None:
        upgrade = self.headers.get("Upgrade", "").lower()
        ws_key = self.headers.get("Sec-WebSocket-Key", "").strip()
        if "websocket" not in upgrade or not ws_key:
            self.close_connection = True
            return self.error(426, "upgrade_required", "Yêu cầu nâng cấp WebSocket cho /v1/sync.")

        ip = self.client_ip()
        if not SYNC_HUB.can_accept_ip(ip):
            self.close_connection = True
            return self.error(429, "too_many_connections", "Quá nhiều kết nối đồng bộ đang hoạt động.")

        accept = base64.b64encode(hashlib.sha1((ws_key + WS_GUID).encode("utf-8")).digest()).decode("ascii")
        self.close_connection = True
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.wfile.flush()

        # Perform blocking WebSocket relay loop inside this handler thread until closed.
        client = None
        try:
            self.connection.settimeout(12.0)
            tmp_client = SyncClient(self, ip, "pending", "unknown", "")
            first = _ws_read_message(self, tmp_client)
            if first is None:
                return
            _, raw_bytes = first
            try:
                hello = json.loads(raw_bytes.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                _ws_send_frame(tmp_client, 0x8, struct.pack("!H", 1003))
                return

            if not isinstance(hello, dict) or hello.get("type") != "relay_join":
                _ws_send_json(tmp_client, {"type": "relay_error", "message": "First message must be relay_join"})
                _ws_send_frame(tmp_client, 0x8, struct.pack("!H", 1002))
                return

            room = str(hello.get("room", "")).strip().lower()
            if not ROOM_RE.match(room):
                raw_key = str(hello.get("key", "")).strip()
                if len(raw_key) >= 4:
                    room = hashlib.sha256(("3012-room-v1:" + raw_key).encode("utf-8")).hexdigest()
                else:
                    _ws_send_json(tmp_client, {"type": "relay_error", "message": "Invalid room hash"})
                    _ws_send_frame(tmp_client, 0x8, struct.pack("!H", 1008))
                    return

            role = str(hello.get("role", "mobile")).strip().lower()
            if role not in ("pc", "mobile", "viewer"):
                role = "mobile"
            cid = str(hello.get("clientId", "")).strip()
            if not CLIENT_ID_RE.match(cid):
                cid = uuid.uuid4().hex[:12]

            client = SyncClient(self, ip, cid, role, room)
            existing = SYNC_HUB.join(client)
            if existing is None:
                _ws_send_json(tmp_client, {"type": "relay_error", "message": "Sync room full"})
                _ws_send_frame(tmp_client, 0x8, struct.pack("!H", 1013))
                return

            self.connection.settimeout(75.0)
            _ws_send_json(
                client,
                {
                    "type": "relay_joined",
                    "clientId": client.client_id,
                    "peers": [{"clientId": p.client_id, "role": p.role} for p in existing],
                },
            )
            for peer in existing:
                _ws_send_json(peer, {"type": "relay_peer_joined", "clientId": client.client_id, "role": client.role})

            while not client.closed:
                frame = _ws_read_message(self, client)
                if frame is None:
                    break
                _, msg_bytes = frame
                try:
                    pkt = json.loads(msg_bytes.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                if not isinstance(pkt, dict):
                    continue
                ptype = pkt.get("type")
                if ptype == "relay_ping":
                    _ws_send_json(client, {"type": "relay_pong", "ts": pkt.get("ts", 0)})
                elif ptype == "relay_packet":
                    encrypted = pkt.get("p")
                    if not isinstance(encrypted, str) or not encrypted:
                        continue
                    forward = {"type": "relay_packet", "from": client.client_id, "role": client.role, "p": encrypted}
                    for peer in SYNC_HUB.peers_for(client):
                        _ws_send_json(peer, forward)
        except (EOFError, TimeoutError, socket.timeout, OSError):
            pass
        finally:
            if client is not None:
                remaining = SYNC_HUB.leave(client)
                for peer in remaining:
                    _ws_send_json(peer, {"type": "relay_peer_left", "clientId": client.client_id, "role": client.role})

    def do_GET(self):
        url = urlparse(self.path)
        parts = [p for p in url.path.split("/") if p]
        if parts == ["v1", "sync"]:
            return self.handle_sync_websocket()
        if parts == ["sync.mjs"]:
            host = (self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or "").split(",")[0].strip()
            if host and not host.startswith(("127.0.0.1", "localhost", "[::1]")):
                relay_default = f"wss://{host}/v1/sync"
            else:
                relay_default = "wss://build.kaydus.xyz/v1/sync"
            script = SYNC_MJS_TEMPLATE.replace("__DEFAULT_RELAY__", relay_default)
            return self.send_text(200, script, "text/javascript; charset=utf-8")

        sync_stats = SYNC_HUB.stats()
        build_stats = QUEUE.stats()
        if parts == []:
            if "text/html" in self.headers.get("Accept", "").lower():
                html_doc = f"""<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>3012 Theos Build &amp; Sync Relay Server</title>
<style>
  body{{margin:0;background:#0A0D12;color:#F1F5F9;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;display:grid;place-items:center;min-height:100vh;padding:24px}}
  .card{{max-width:560px;width:100%;background:#141A22;border:1px solid #263040;border-radius:12px;padding:24px;box-sizing:border-box}}
  .badge{{display:inline-block;padding:4px 10px;border-radius:6px;background:rgba(16,185,129,.16);color:#10B981;font-size:12px;font-weight:700;letter-spacing:.04em}}
  h1{{margin:14px 0 8px;font-size:20px}}
  p{{color:#94A3B8;font-size:13px;line-height:1.55}}
  .grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:18px 0}}
  .stat{{background:#0D1117;border:1px solid #1E293B;border-radius:8px;padding:10px}}
  .stat b{{display:block;font-size:18px;color:#F8FAFC;margin-top:4px}}
  .stat span{{font-size:11px;color:#64748B;text-transform:uppercase}}
  code{{background:#0D1117;padding:2px 6px;border-radius:4px;color:#E2E8F0}}
</style>
</head>
<body>
  <div class="card">
    <span class="badge">3012 BUILD &amp; SYNC SERVER v{VERSION} — ONLINE</span>
    <h1>Theos Sandbox + Zero-Knowledge E2EE Sync</h1>
    <p>Máy chủ biên dịch <code>.deb</code> / <code>.dylib</code> cách ly bằng Docker và trạm tiếp vận WebSocket mã hóa đầu cuối <code>AES-256-GCM</code> cho <strong>3012</strong>.</p>
    <div class="grid">
      <div class="stat"><span>Đang build</span><b>{build_stats["running"]}/{build_stats["capacity"]}</b></div>
      <div class="stat"><span>Hàng đợi</span><b>{build_stats["queued"]}</b></div>
      <div class="stat"><span>Sync Rooms</span><b>{sync_stats["syncRooms"]}</b></div>
      <div class="stat"><span>Clients</span><b>{sync_stats["syncClients"]}</b></div>
    </div>
    <p>Endpoints: <code>/v1/health</code> • <code>POST /v1/builds/cas</code> • <code>POST /v1/builds</code> • <code>WS /v1/sync</code></p>
  </div>
</body>
</html>"""
                return self.send_text(200, html_doc, "text/html; charset=utf-8")
            body = {
                "ok": True,
                "version": VERSION,
                "syncRelay": True,
                "casDelta": True,
                **build_stats,
                **sync_stats,
                "limits": {
                    "maxUploadMB": CFG["max_upload"] // (1024 * 1024),
                    "maxProjectMB": CFG["max_project_mb"],
                    "casBatchMB": CFG["cas_batch_bytes"] // (1024 * 1024),
                    "timeoutSec": CFG["timeout"],
                    "perDeviceHour": CFG["rate_device"],
                },
            }
            return self.send_json(200, body)
        if parts == ["v1", "health"]:
            body = {
                "ok": True,
                "version": VERSION,
                "syncRelay": True,
                "casDelta": True,
                **build_stats,
                **sync_stats,
                "limits": {
                    "maxUploadMB": CFG["max_upload"] // (1024 * 1024),
                    "maxProjectMB": CFG["max_project_mb"],
                    "casBatchMB": CFG["cas_batch_bytes"] // (1024 * 1024),
                    "timeoutSec": CFG["timeout"],
                    "perDeviceHour": CFG["rate_device"],
                },
            }
            return self.send_json(200, body)
        if len(parts) == 3 and parts[:2] == ["v1", "builds"]:
            job = self.find_job(parts[2])
            if not job:
                return self.error(404, "not_found", "Không tìm thấy build (có thể đã hết hạn).")
            req_dev = self.headers.get("X-Device-ID", "").strip()
            if req_dev and req_dev != job.device:
                return self.error(403, "forbidden", "Không có quyền xem build này.")
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
                fh = open(path, "rb")
            except OSError:
                return self.error(410, "gone", "File đã hết hạn.")
            try:
                size = os.fstat(fh.fileno()).st_size
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(size))
                self.send_header("Content-Disposition", f'attachment; filename="{name}"')
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                shutil.copyfileobj(fh, self.wfile)
            except (BrokenPipeError, ConnectionResetError):
                self.close_connection = True
            except OSError:
                self.close_connection = True
            finally:
                fh.close()
            return None
        return self.error(404, "not_found", "Endpoint không tồn tại.")

    def read_limited_body(self, max_bytes: int):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            self.close_connection = True
            self.error(411, "length_required", "Thiếu Content-Length.")
            return None
        if length > max_bytes:
            self.close_connection = True
            self.error(413, "too_large", f"Payload vượt quá giới hạn {max(1, max_bytes // (1024 * 1024))} MB.")
            return None
        buf = bytearray()
        remaining = length
        while remaining > 0:
            chunk = self.rfile.read(min(65536, remaining))
            if not chunk:
                break
            buf.extend(chunk)
            remaining -= len(chunk)
        if remaining != 0:
            self.close_connection = True
            self.error(400, "bad_stream", "Dữ liệu tải lên bị ngắt quãng.")
            return None
        return bytes(buf)

    def _read_exact_from_payload(self, n: int, state: dict):
        if n < 0 or n > state["remaining"]:
            return None
        buf = bytearray()
        left = n
        while left > 0:
            chunk = self.rfile.read(min(65536, left))
            if not chunk:
                return None
            buf.extend(chunk)
            left -= len(chunk)
            state["remaining"] -= len(chunk)
        return bytes(buf)

    def handle_cas_check(self, device: str):
        raw = self.read_limited_body(2 * 1024 * 1024)
        if raw is None:
            return None
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return self.error(400, "bad_json", "JSON không hợp lệ.")
        hashes = payload.get("hashes") if isinstance(payload, dict) else None
        if not isinstance(hashes, list) or len(hashes) > 20000:
            return self.error(400, "bad_hashes", "Danh sách hashes không hợp lệ (tối đa 20000).")
        missing = CAS_STORE.missing_hashes(hashes)
        return self.send_json(
            200,
            {
                "ok": True,
                "missing": missing,
                "chunkMaxBytes": CAS_CHUNK_MAX,
                "batchMaxBytes": CFG["cas_batch_bytes"],
                "maxProjectMB": CFG["max_project_mb"],
            },
        )

    def handle_cas_upload(self, device: str):
        if not QUEUE.allow_upload_batch(self.client_ip()):
            self.close_connection = True
            return self.error(429, "rate_limited", "Tốc độ upload chunk tạm thời vượt giới hạn. Vui lòng thử lại sau.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        max_body = CFG["cas_batch_bytes"] + 262144
        if length <= 12:
            self.close_connection = True
            return self.error(400, "bad_stream", "Payload CAS quá ngắn.")
        if length > max_body:
            self.close_connection = True
            return self.error(413, "too_large", f"Batch vượt quá giới hạn {CFG['cas_batch_bytes'] // (1024 * 1024)} MB.")
        if disk_usage_percent() >= CFG["disk_max_percent"]:
            prune_storage(force=True)
            if disk_usage_percent() >= CFG["disk_max_percent"]:
                self.close_connection = True
                return self.error(503, "disk_full", "Máy chủ tạm ngừng nhận dữ liệu (ổ đĩa gần đầy).")

        os.makedirs(CAS_STORE.tmp_dir(), exist_ok=True)
        state = {"remaining": length}
        header = self._read_exact_from_payload(12, state)
        if header is None or header[:8] != CAS_MAGIC:
            self.close_connection = True
            return self.error(400, "bad_magic", "Sai định dạng luồng CAS.")
        (count,) = struct.unpack("!I", header[8:12])
        if count < 1 or count > 2500:
            self.close_connection = True
            return self.error(400, "bad_count", "Số lượng chunk trong batch không hợp lệ.")

        total_bytes = 0
        for _ in range(count):
            meta = self._read_exact_from_payload(36, state)
            if meta is None:
                self.close_connection = True
                return self.error(400, "bad_stream", "Thiếu header chunk trong luồng CAS.")
            digest_raw = meta[:32]
            (blob_len,) = struct.unpack("!I", meta[32:36])
            if blob_len > CAS_CHUNK_MAX or blob_len > state["remaining"]:
                self.close_connection = True
                return self.error(400, "bad_chunk_size", "Kích thước chunk vượt giới hạn.")
            sha_hex = digest_raw.hex()
            tmp_path = os.path.join(CAS_STORE.tmp_dir(), f"{uuid.uuid4().hex}.part")
            hasher = hashlib.sha256()
            left = blob_len
            aborted = False
            try:
                with open(tmp_path, "wb") as dst:
                    while left > 0:
                        part = self.rfile.read(min(65536, left))
                        if not part:
                            aborted = True
                            break
                        state["remaining"] -= len(part)
                        hasher.update(part)
                        dst.write(part)
                        left -= len(part)
                if aborted or hasher.digest() != digest_raw:
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.close_connection = True
                    return self.error(400, "bad_hash" if not aborted else "bad_stream", "Mã băm SHA-256 của chunk không khớp.")
                if sha_hex != EMPTY_SHA256:
                    CAS_STORE.commit_temp_blob(sha_hex, tmp_path)
                else:
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                total_bytes += blob_len
            except OSError:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
                self.close_connection = True
                return self.error(500, "io_error", "Không thể ghi chunk lên ổ đĩa máy chủ.")

        if state["remaining"] != 0:
            self.close_connection = True
            return self.error(400, "bad_stream", "Dữ liệu thừa cuối luồng CAS.")

        CAS_STORE.prune()
        return self.send_json(200, {"ok": True, "stored": count, "bytes": total_bytes})

    def handle_cas_build(self, device: str):
        raw = self.read_limited_body(4 * 1024 * 1024)
        if raw is None:
            return None
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return self.error(400, "bad_json", "Manifest JSON không hợp lệ.")
        if not isinstance(payload, dict):
            return self.error(400, "bad_manifest", "Manifest phải là JSON object.")

        scheme = str(payload.get("scheme") or self.headers.get("X-Package-Scheme", "rootless")).strip().lower()
        if scheme not in SCHEMES:
            return self.error(400, "bad_scheme", "X-Package-Scheme phải là rootless, rootful hoặc roothide.")

        clean_hdr = self.headers.get("X-Clean-Build", "").strip() == "1"
        clean_build = bool(payload.get("clean", clean_hdr))
        project_slug = sanitize_slug(str(payload.get("projectName") or "project"))
        files_raw = payload.get("files")
        if not isinstance(files_raw, list) or not files_raw or len(files_raw) > CFG["max_project_files"]:
            return self.error(400, "bad_files", f"Dự án phải có từ 1 đến {CFG['max_project_files']} file.")

        max_proj_bytes = CFG["max_project_mb"] * 1024 * 1024
        seen_paths = set()
        normalized_files = []
        total_size = 0
        referenced_hashes = []

        for item in files_raw:
            if not isinstance(item, dict):
                return self.error(400, "bad_manifest", "Mục file không hợp lệ.")
            rel = validate_rel_path(item.get("path"))
            if not rel or rel in seen_paths:
                return self.error(400, "bad_path", "Đường dẫn file không hợp lệ hoặc bị trùng.")
            seen_paths.add(rel)

            fsize = item.get("size")
            if not isinstance(fsize, int) or isinstance(fsize, bool) or fsize < 0 or fsize > max_proj_bytes:
                return self.error(400, "bad_size", f"Kích thước file {rel} không hợp lệ.")
            chunks_raw = item.get("chunks")
            if not isinstance(chunks_raw, list) or len(chunks_raw) > 64:
                return self.error(400, "bad_chunks", f"Danh sách chunks của {rel} không hợp lệ.")

            if fsize == 0:
                if chunks_raw and not (len(chunks_raw) == 1 and str(chunks_raw[0]).lower() == EMPTY_SHA256):
                    return self.error(400, "bad_chunks", f"File rỗng {rel} không khớp chunks.")
                norm_chunks = []
            else:
                if not chunks_raw:
                    return self.error(400, "bad_chunks", f"File {rel} thiếu chunk hash.")
                norm_chunks = []
                for c in chunks_raw:
                    if not isinstance(c, str):
                        return self.error(400, "bad_chunks", f"Hash chunk không hợp lệ trong {rel}.")
                    low = c.strip().lower()
                    if not SHA256_RE.match(low):
                        return self.error(400, "bad_chunks", f"Hash chunk không hợp lệ trong {rel}.")
                    norm_chunks.append(low)
                    if low != EMPTY_SHA256:
                        referenced_hashes.append(low)

            total_size += fsize
            if total_size > max_proj_bytes:
                self.close_connection = True
                return self.error(413, "too_large", f"Tổng dung lượng dự án vượt quá {CFG['max_project_mb']} MB.")

            normalized_files.append(
                {
                    "path": rel,
                    "size": fsize,
                    "chunks": norm_chunks,
                    "exec": bool(item.get("exec", False)),
                }
            )

        missing = CAS_STORE.missing_hashes(referenced_hashes)
        if missing:
            return self.send_json(
                409,
                {
                    "error": "missing_blobs",
                    "missing": missing,
                    "message": f"Thiếu {len(missing)} khối dữ liệu trên máy chủ, cần tải lên bổ sung.",
                },
            )

        # Verify assembled blob sizes match declared file sizes
        for entry in normalized_files:
            if entry["size"] > 0:
                actual = 0
                for sha in entry["chunks"]:
                    if sha == EMPTY_SHA256:
                        continue
                    try:
                        actual += os.path.getsize(CAS_STORE.blob_path(sha))
                    except OSError:
                        return self.send_json(
                            409,
                            {"error": "missing_blobs", "missing": [sha], "message": "Khối dữ liệu vừa bị dọn, hãy tải lại."},
                        )
                if actual != entry["size"]:
                    return self.error(400, "size_mismatch", f"Kích thước thực tế của {entry['path']} không khớp manifest.")

        if disk_usage_percent() >= CFG["disk_max_percent"]:
            prune_storage(force=True)
            if disk_usage_percent() >= CFG["disk_max_percent"]:
                self.close_connection = True
                return self.error(503, "disk_full", "Máy chủ tạm ngừng nhận build (ổ đĩa gần đầy).")

        job_id = uuid.uuid4().hex
        manifest_obj = {"projectName": project_slug, "files": normalized_files}
        job, err = QUEUE.submit(
            job_id,
            device,
            self.client_ip(),
            scheme,
            payload_path="",
            manifest=manifest_obj,
            clean_build=clean_build,
            project_slug=project_slug,
        )
        if err:
            code, message = err
            return self.error(503 if code == "queue_full" else 429, code, message)
        log(f"job={job.id[:8]} device={short_hash(device)} queued_cas files={len(normalized_files)} size={total_size}")
        return self.send_json(202, self.job_view(job, 0))

    def do_POST(self):
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        if parts not in (["v1", "builds"], ["v1", "builds", "cas"], ["v1", "cas", "check"], ["v1", "cas", "upload"]):
            self.close_connection = True
            return self.error(404, "not_found", "Endpoint không tồn tại.")

        device = self.headers.get("X-Device-ID", "").strip()
        if not DEVICE_RE.match(device):
            self.close_connection = True
            return self.error(400, "bad_device", "Thiếu hoặc sai X-Device-ID.")

        if parts == ["v1", "cas", "check"]:
            return self.handle_cas_check(device)
        if parts == ["v1", "cas", "upload"]:
            return self.handle_cas_upload(device)
        if parts == ["v1", "builds", "cas"]:
            return self.handle_cas_build(device)

        scheme = self.headers.get("X-Package-Scheme", "rootless").strip().lower()
        if scheme not in SCHEMES:
            self.close_connection = True
            return self.error(400, "bad_scheme", "X-Package-Scheme phải là rootless, rootful hoặc roothide.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            self.close_connection = True
            return self.error(411, "length_required", "Thiếu Content-Length.")
        if length > CFG["max_upload"]:
            self.close_connection = True
            return self.error(413, "too_large", f"Project vượt quá {CFG['max_upload'] // (1024 * 1024)} MB.")
        if disk_usage_percent() >= CFG["disk_max_percent"]:
            prune_storage(force=True)
            if disk_usage_percent() >= CFG["disk_max_percent"]:
                self.close_connection = True
                return self.error(503, "disk_full", "Máy chủ tạm ngừng nhận build (ổ đĩa gần đầy).")

        job_id = uuid.uuid4().hex
        qpath = queue_file(job_id)
        remaining = length
        header_buf = bytearray()
        try:
            os.makedirs(os.path.dirname(qpath), exist_ok=True)
            with open(qpath, "wb") as dst:
                while remaining > 0:
                    chunk = self.rfile.read(min(65536, remaining))
                    if not chunk:
                        break
                    if len(header_buf) < 4:
                        header_buf.extend(chunk[: 4 - len(header_buf)])
                    dst.write(chunk)
                    remaining -= len(chunk)
        except OSError:
            remove_queue_file(job_id)
            self.close_connection = True
            return self.error(500, "io_error", "Không lưu được dữ liệu build.")

        if remaining != 0 or not bytes(header_buf).startswith(b"PK\x03\x04"):
            remove_queue_file(job_id)
            return self.error(400, "bad_zip", "Dữ liệu tải lên không phải file .zip hợp lệ.")

        job, err = QUEUE.submit(job_id, device, self.client_ip(), scheme, qpath)
        if err:
            remove_queue_file(job_id)
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
    for sub in ("artifacts", "queue", "cas", os.path.join("cas", "tmp"), "workspaces", "stages"):
        os.makedirs(os.path.join(CFG["data_dir"], sub), exist_ok=True)
    for entry in os.listdir(os.path.join(CFG["data_dir"], "artifacts")):
        shutil.rmtree(artifact_dir(entry), ignore_errors=True)
    for entry in os.listdir(os.path.join(CFG["data_dir"], "stages")):
        shutil.rmtree(stage_dir(entry), ignore_errors=True)
    for entry in os.listdir(os.path.join(CFG["data_dir"], "cas", "tmp")):
        try:
            os.unlink(os.path.join(CFG["data_dir"], "cas", "tmp", entry))
        except OSError:
            pass
    for entry in os.listdir(os.path.join(CFG["data_dir"], "queue")):
        try:
            os.unlink(os.path.join(CFG["data_dir"], "queue", entry))
        except OSError:
            pass

    prune_storage(force=False)

    try:
        stray = subprocess.run(["docker", "ps", "-q", "--filter", "name=b3012-"], capture_output=True, text=True, timeout=5)
        for cid in stray.stdout.split():
            subprocess.run(["docker", "kill", cid], capture_output=True, timeout=5)
    except (OSError, subprocess.SubprocessError) as exc:
        log(f"docker cleanup skipped: {exc}")

    for _ in range(CFG["concurrency"]):
        threading.Thread(target=worker_loop, daemon=True).start()
    threading.Thread(target=janitor_loop, daemon=True).start()

    server = ThreadingHTTPServer((CFG["bind"], CFG["port"]), Handler)
    server.daemon_threads = True
    log(
        f"3012 build & sync relay server {VERSION} listening on {CFG['bind']}:{CFG['port']} "
        f"(concurrency={CFG['concurrency']}, image={CFG['image']})"
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
