"use strict";

const vscode = require("vscode");
const http = require("http");
const net = require("net");
const tls = require("tls");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn } = require("child_process");

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const SECRET_STORAGE_KEY = "3012sync.permanentKey";
const MAX_WS_MESSAGE = 16 * 1024 * 1024;
const IGNORED_NAMES = new Set([
  ".git",
  "node_modules",
  ".next",
  "dist",
  "build",
  ".DS_Store",
  "__pycache__",
  ".venv",
  ".build",
  ".idea"
]);

function deriveRoomID(secret) {
  return crypto
    .createHash("sha256")
    .update("3012-room-v1:" + String(secret || "").trim(), "utf8")
    .digest("hex");
}

function deriveAESKey(secret) {
  return crypto
    .createHash("sha256")
    .update("3012-e2ee-v1:" + String(secret || "").trim(), "utf8")
    .digest();
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

function randomPermanentKey() {
  return "k3012_" + crypto.randomBytes(12).toString("base64url");
}

function randomPin6() {
  return String(crypto.randomInt(100000, 1000000));
}

function getLanIP() {
  const nets = os.networkInterfaces();
  for (const list of Object.values(nets)) {
    for (const info of list || []) {
      if (info.family === "IPv4" && !info.internal) {
        return info.address;
      }
    }
  }
  return "127.0.0.1";
}

function isTextBuffer(buf) {
  const sample = buf.subarray(0, Math.min(buf.length, 4096));
  for (let i = 0; i < sample.length; i++) {
    if (sample[i] === 0) return false;
  }
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
    header[0] = 0x80 | opcode;
    header[1] = maskBit | 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = maskBit | 127;
    header.writeBigUInt64BE(BigInt(len), 2);
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
  let ended = false;

  function fireClose() {
    if (ended) return;
    ended = true;
    onClose();
  }

  socket.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    while (buf.length >= 2) {
      const b1 = buf[0];
      const b2 = buf[1];
      const fin = (b1 & 0x80) !== 0;
      const opcode = b1 & 0x0f;
      const masked = (b2 & 0x80) !== 0;
      let payloadLen = b2 & 0x7f;
      let offset = 2;
      if (payloadLen === 126) {
        if (buf.length < 4) return;
        payloadLen = buf.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (buf.length < 10) return;
        payloadLen = Number(buf.readBigUInt64BE(2));
        offset = 10;
      }
      if (payloadLen > MAX_WS_MESSAGE) {
        socket.destroy();
        fireClose();
        return;
      }
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

      if (opcode === 0x8) {
        socket.end();
        fireClose();
        return;
      }
      if (opcode === 0x9) {
        try {
          socket.write(encodeWsFrame(0x0a, payload.subarray(0, 125), false));
        } catch {}
        continue;
      }
      if (opcode === 0x0a) continue;

      if (opcode === 0x1 || opcode === 0x2) {
        frags = [payload];
        fragLen = payload.length;
        collecting = !fin;
        if (fin) onMessage(Buffer.concat(frags));
      } else if (opcode === 0x0 && collecting) {
        fragLen += payload.length;
        if (fragLen > MAX_WS_MESSAGE) {
          socket.destroy();
          fireClose();
          return;
        }
        frags.push(payload);
        if (fin) {
          collecting = false;
          onMessage(Buffer.concat(frags));
        }
      }
    }
  });
  socket.on("close", fireClose);
  socket.on("error", fireClose);
}

class SyncController {
  constructor(context) {
    this.context = context;
    this.output = vscode.window.createOutputChannel("3012 Mobile Sync");
    this.statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 120);
    this.statusBar.command = "3012sync.menu";
    this.statusBar.show();

    this.clientId = "vsc-" + crypto.randomBytes(6).toString("hex");
    this.permanentKey = "";
    this.quickPin = "";
    this.relayReady = false;
    this.peerOnline = false;
    this.lanServer = null;
    this.lanPort = 30120;
    this.lanClients = new Set();
    this.relayWorkers = [];
    this.suppressed = new Map();
    this.changeTimers = new Map();
    this.disposables = [];
    this.active = false;
  }

  getRoot() {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders || folders.length === 0) return "";
    return folders[0].uri.fsPath;
  }

  cfg() {
    return vscode.workspace.getConfiguration("3012sync");
  }

  relayUrl() {
    return String(this.cfg().get("relayUrl", "wss://build.kaydus.xyz/v1/sync") || "wss://build.kaydus.xyz/v1/sync").trim();
  }

  autoSaveIncoming() {
    return Boolean(this.cfg().get("autoSaveIncomingEdits", true));
  }

  suppressEcho(rel) {
    this.suppressed.set(rel, Date.now() + 1200);
  }

  isSuppressed(rel) {
    const exp = this.suppressed.get(rel);
    if (!exp) return false;
    if (Date.now() > exp) {
      this.suppressed.delete(rel);
      return false;
    }
    return true;
  }

  safeResolve(relPath) {
    const root = this.getRoot();
    if (!root) return null;
    const clean = String(relPath || "").replace(/\\/g, "/").replace(/^\/+/, "");
    if (!clean || clean === "." || clean.split("/").some((s) => s === ".." || s === "")) return null;
    const abs = path.resolve(root, clean);
    if (abs !== root && !abs.startsWith(root + path.sep)) return null;
    try {
      let probe = abs;
      while (probe !== root && !fs.existsSync(probe)) {
        probe = path.dirname(probe);
      }
      const realProbe = fs.realpathSync(probe);
      const realRoot = fs.realpathSync(root);
      if (realProbe !== realRoot && !realProbe.startsWith(realRoot + path.sep)) return null;
    } catch {
      return null;
    }
    return abs;
  }

  relPathForFs(fsPath) {
    const root = this.getRoot();
    if (!root) return null;
    const rel = path.relative(root, fsPath).split(path.sep).join("/");
    if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) return null;
    const parts = rel.split("/");
    if (parts.some((p) => IGNORED_NAMES.has(p) || p.startsWith(".3012"))) return null;
    return rel;
  }

  collectSnapshot() {
    const root = this.getRoot();
    const out = {};
    if (!root) return out;

    const walk = (dir, base) => {
      let entries = [];
      try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
      } catch {
        return;
      }
      for (const entry of entries) {
        if (IGNORED_NAMES.has(entry.name) || entry.name.startsWith(".3012")) continue;
        if (entry.isSymbolicLink()) continue;
        const rel = base ? `${base}/${entry.name}` : entry.name;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          walk(full, rel);
        } else if (entry.isFile()) {
          try {
            const st = fs.lstatSync(full);
            if (st.isSymbolicLink() || !st.isFile() || st.size > 512 * 1024) continue;
            const buf = fs.readFileSync(full);
            if (isTextBuffer(buf)) out[rel] = buf.toString("utf8");
          } catch {}
        }
      }
    };
    walk(root, "");

    // Overlay unsaved open editor buffers so phone sees latest live edits even before Cmd+S
    for (const doc of vscode.workspace.textDocuments) {
      if (doc.uri.scheme !== "file" || !doc.isDirty) continue;
      const rel = this.relPathForFs(doc.uri.fsPath);
      if (rel) out[rel] = doc.getText();
    }
    return out;
  }

  updateStatusBar() {
    if (!this.active) {
      this.statusBar.text = "$(plug) 3012 Sync";
      this.statusBar.tooltip = "Bấm để kết nối & đồng bộ 2 chiều với 3012 trên iPhone/iPad";
      return;
    }
    if (this.peerOnline || this.lanClients.size > 0) {
      this.statusBar.text = "$(check) 3012 Sync Live";
      this.statusBar.tooltip = `Đã kết nối với 3012 iOS • Relay: ${this.relayUrl()}`;
    } else if (this.quickPin) {
      this.statusBar.text = `$(key) 3012 PIN: ${this.quickPin}`;
      this.statusBar.tooltip = `Nhập PIN ${this.quickPin} trong app 3012 (tự nhớ khóa vĩnh viễn)`;
    } else if (this.relayReady) {
      this.statusBar.text = "$(radio-tower) 3012 Sẵn sàng";
      this.statusBar.tooltip = `Đang chờ 3012 trên iPhone mở • Relay: ${this.relayUrl()}`;
    } else {
      this.statusBar.text = "$(sync~spin) 3012 Đang nối...";
      this.statusBar.tooltip = `Đang kết nối ${this.relayUrl()}`;
    }
  }

  broadcast(obj, exceptSocket = null) {
    if (!this.active) return;
    const lanFrame = encodeWsFrame(0x1, Buffer.from(JSON.stringify(obj), "utf8"), false);
    for (const c of this.lanClients) {
      if (c.socket !== exceptSocket && c.authenticated && !c.socket.destroyed) {
        try {
          c.socket.write(lanFrame);
        } catch {}
      }
    }
    for (const w of this.relayWorkers) {
      if (w.ready) w.sendApp(obj);
    }
  }

  async applyIncomingUpsert(rel, content) {
    const abs = this.safeResolve(rel);
    if (!abs) return;
    this.suppressEcho(rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, content, "utf8");

    const uri = vscode.Uri.file(abs);
    const openDoc = vscode.workspace.textDocuments.find((d) => d.uri.fsPath === abs);
    if (openDoc && openDoc.getText() !== content) {
      const edit = new vscode.WorkspaceEdit();
      const fullRange = new vscode.Range(
        openDoc.positionAt(0),
        openDoc.positionAt(openDoc.getText().length)
      );
      edit.replace(uri, fullRange, content);
      await vscode.workspace.applyEdit(edit);
      if (this.autoSaveIncoming()) {
        await openDoc.save();
      }
    }
    this.output.appendLine(`[<- Mobile] ${rel}`);
  }

  async handleProtocolMessage(msg, replyFn, broadcastExceptSocket = null, isPinRoom = false) {
    if (!msg || typeof msg !== "object") return;
    const root = this.getRoot();
    if (msg.type === "hello") {
      replyFn({
        type: "welcome",
        projectName: root ? path.basename(root) : "VS Code Workspace",
        rootDir: root,
        lanUrl: `ws://${getLanIP()}:${this.lanPort}`,
        lanToken: this.permanentKey,
        issuedPermanentKey: isPinRoom ? this.permanentKey : undefined
      });
      this.peerOnline = true;
      this.updateStatusBar();
      return;
    }
    if (msg.type === "ping") {
      replyFn({ type: "pong", ts: msg.ts });
      return;
    }
    if (msg.type === "request_snapshot") {
      replyFn({ type: "snapshot", files: this.collectSnapshot() });
      return;
    }
    if (msg.type === "push_snapshot" && msg.files && typeof msg.files === "object") {
      for (const [rel, body] of Object.entries(msg.files)) {
        if (typeof body === "string") await this.applyIncomingUpsert(rel, body);
      }
      return;
    }
    if (msg.type === "upsert" && typeof msg.path === "string" && typeof msg.content === "string") {
      await this.applyIncomingUpsert(msg.path, msg.content);
      this.broadcast(msg, broadcastExceptSocket);
      return;
    }
    if (msg.type === "delete" && typeof msg.path === "string") {
      const abs = this.safeResolve(msg.path);
      if (abs && fs.existsSync(abs)) {
        this.suppressEcho(msg.path);
        fs.rmSync(abs, { recursive: true, force: true });
        this.broadcast(msg, broadcastExceptSocket);
        this.output.appendLine(`[<- Mobile DELETE] ${msg.path}`);
      }
      return;
    }
    if (msg.type === "rename" && msg.oldPath && msg.path) {
      const src = this.safeResolve(msg.oldPath);
      const dst = this.safeResolve(msg.path);
      if (src && dst && fs.existsSync(src)) {
        this.suppressEcho(msg.oldPath);
        this.suppressEcho(msg.path);
        fs.mkdirSync(path.dirname(dst), { recursive: true });
        fs.renameSync(src, dst);
        this.broadcast(msg, broadcastExceptSocket);
      }
      return;
    }
    if (msg.type === "mkdir" && msg.path) {
      const abs = this.safeResolve(msg.path);
      if (abs) {
        fs.mkdirSync(abs, { recursive: true });
        this.broadcast(msg, broadcastExceptSocket);
      }
      return;
    }
    if (msg.type === "exec_cmd" && msg.command) {
      if (!root) {
        replyFn({ type: "cmd_result", id: msg.id || "", exitCode: -1, stdout: "", stderr: "Chưa mở thư mục nào trong VS Code." });
        return;
      }
      const child = spawn(msg.command, { cwd: root, shell: true });
      let stdout = "";
      let stderr = "";
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

  startLanServer() {
    this.stopLanServer();
    const desiredPort = Number(this.cfg().get("lanPort", 30120) || 30120);
    const server = http.createServer((_req, res) => {
      res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("3012 VS Code Sync LAN Endpoint\n");
    });
    server.on("upgrade", (req, socket) => {
      const key = req.headers["sec-websocket-key"];
      if (!key) {
        socket.destroy();
        return;
      }
      const accept = crypto.createHash("sha1").update(key + WS_GUID).digest("base64");
      socket.write([
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Accept: ${accept}`,
        "\r\n"
      ].join("\r\n"));

      const client = { socket, authenticated: false };
      this.lanClients.add(client);
      const replyFn = (o) => {
        if (!socket.destroyed) socket.write(encodeWsFrame(0x1, Buffer.from(JSON.stringify(o), "utf8"), false));
      };

      attachWsDecoder(socket, async (buf) => {
        let msg;
        try {
          msg = JSON.parse(buf.toString("utf8"));
        } catch {
          return;
        }
        if (!client.authenticated) {
          if (msg.type === "hello" && (msg.token === this.permanentKey || (this.quickPin && msg.token === this.quickPin))) {
            client.authenticated = true;
            await this.handleProtocolMessage(msg, replyFn, socket, this.quickPin && msg.token === this.quickPin);
          } else {
            replyFn({ type: "error", message: "Sai Khoa Dong Bo" });
            socket.end();
          }
          return;
        }
        await this.handleProtocolMessage(msg, replyFn, socket, false);
      }, () => {
        this.lanClients.delete(client);
        this.updateStatusBar();
      });
    });

    server.on("error", (err) => {
      this.output.appendLine(`[LAN] Port ${desiredPort} bận (${err.message}), thử cổng tự động...`);
      try {
        server.listen(0, "0.0.0.0", () => {
          const addr = server.address();
          this.lanPort = addr && typeof addr === "object" ? addr.port : desiredPort;
        });
      } catch {}
    });

    server.listen(desiredPort, "0.0.0.0", () => {
      const addr = server.address();
      this.lanPort = addr && typeof addr === "object" ? addr.port : desiredPort;
      this.output.appendLine(`[LAN] Đang lắng nghe ws://${getLanIP()}:${this.lanPort}`);
    });
    this.lanServer = server;
  }

  stopLanServer() {
    for (const c of this.lanClients) {
      try { c.socket.destroy(); } catch {}
    }
    this.lanClients.clear();
    if (this.lanServer) {
      try { this.lanServer.close(); } catch {}
      this.lanServer = null;
    }
  }

  spawnRelayWorker(secret, isPinRoom) {
    const relay = this.relayUrl();
    if (!relay || !secret) return null;
    let u;
    try {
      u = new URL(relay);
    } catch {
      return null;
    }
    const isTLS = u.protocol === "wss:" || u.protocol === "https:";
    const port = Number(u.port || (isTLS ? 443 : 80));
    const pathWithQuery = (u.pathname || "/v1/sync") + (u.search || "");
    const room = deriveRoomID(secret);
    const aesKey = deriveAESKey(secret);
    const worker = { ready: false, closed: false, sock: null, retryMs: 1500, sendApp: () => {} };

    const connectOnce = () => {
      if (worker.closed || !this.active) return;
      const sock = isTLS
        ? tls.connect({ host: u.hostname, port, servername: u.hostname })
        : net.connect({ host: u.hostname, port });
      worker.sock = sock;
      worker.ready = false;

      const wsKey = crypto.randomBytes(16).toString("base64");
      let upgraded = false;
      let headerBuf = Buffer.alloc(0);

      const sendRawJSON = (obj) => {
        if (sock.destroyed) return;
        try {
          sock.write(encodeWsFrame(0x1, Buffer.from(JSON.stringify(obj), "utf8"), true));
        } catch {}
      };
      worker.sendApp = (obj) => {
        sendRawJSON({ type: "relay_packet", p: encryptE2EE(obj, aesKey) });
      };

      const pingTimer = setInterval(() => {
        if (!sock.destroyed && upgraded) {
          try {
            sock.write(encodeWsFrame(0x9, Buffer.from("3012"), true));
          } catch {}
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
          "User-Agent: 3012-VSCode-Extension/5.1",
          "\r\n"
        ].join("\r\n");
        sock.write(req);
      });

      const onData = (chunk) => {
        if (upgraded) return;
        headerBuf = Buffer.concat([headerBuf, chunk]);
        const idx = headerBuf.indexOf("\r\n\r\n");
        if (idx < 0) return;
        const head = headerBuf.subarray(0, idx).toString("latin1");
        const leftover = headerBuf.subarray(idx + 4);
        sock.removeListener("data", onData);
        if (!/^HTTP\/1\.[01]\s+101\b/i.test(head)) {
          sock.destroy();
          return;
        }
        upgraded = true;
        worker.ready = true;
        worker.retryMs = 1500;
        this.relayReady = true;
        this.updateStatusBar();
        sendRawJSON({ type: "relay_join", room, role: "pc", clientId: this.clientId });

        attachWsDecoder(sock, async (buf) => {
          let env;
          try {
            env = JSON.parse(buf.toString("utf8"));
          } catch {
            return;
          }
          if (env.type === "relay_packet" && typeof env.p === "string") {
            let msg = null;
            try {
              msg = decryptE2EE(env.p, aesKey);
            } catch {
              return;
            }
            if (!msg) return;
            await this.handleProtocolMessage(msg, worker.sendApp, null, isPinRoom);
            if (isPinRoom && msg.type === "hello") {
              this.output.appendLine("[3012 Sync] Đã trao Khóa Vĩnh Viễn cho iPhone qua mã PIN.");
            }
          } else if (env.type === "relay_joined") {
            if (Array.isArray(env.peers) && env.peers.length > 0) {
              this.peerOnline = true;
              this.updateStatusBar();
            }
          } else if (env.type === "relay_peer_joined") {
            this.peerOnline = true;
            this.updateStatusBar();
          } else if (env.type === "relay_peer_left") {
            this.peerOnline = false;
            this.updateStatusBar();
          }
        }, () => {
          clearInterval(pingTimer);
          worker.ready = false;
        });

        if (leftover.length > 0) sock.emit("data", leftover);
      };

      sock.on("data", onData);
      sock.on("close", () => {
        clearInterval(pingTimer);
        worker.ready = false;
        this.relayReady = this.relayWorkers.some((w) => w.ready);
        this.updateStatusBar();
        if (!worker.closed && this.active) {
          const delay = worker.retryMs;
          worker.retryMs = Math.min(worker.retryMs * 2, 15000);
          setTimeout(connectOnce, delay);
        }
      });
      sock.on("error", (err) => {
        this.output.appendLine(`[Relay] Lỗi: ${err.message}`);
      });
    };

    connectOnce();
    return worker;
  }

  stopRelayWorkers() {
    for (const w of this.relayWorkers) {
      w.closed = true;
      w.ready = false;
      try { w.sock && w.sock.destroy(); } catch {}
    }
    this.relayWorkers = [];
    this.relayReady = false;
    this.peerOnline = false;
  }

  installWatchers() {
    this.disposeWatchers();
    this.disposables.push(
      vscode.workspace.onDidChangeTextDocument((ev) => {
        if (!this.active || ev.document.uri.scheme !== "file" || ev.contentChanges.length === 0) return;
        const rel = this.relPathForFs(ev.document.uri.fsPath);
        if (!rel || this.isSuppressed(rel)) return;
        const oldTimer = this.changeTimers.get(rel);
        if (oldTimer) clearTimeout(oldTimer);
        const text = ev.document.getText();
        const t = setTimeout(() => {
          this.changeTimers.delete(rel);
          if (!this.isSuppressed(rel)) {
            this.broadcast({ type: "upsert", path: rel, content: text });
          }
        }, 300);
        this.changeTimers.set(rel, t);
      }),
      vscode.workspace.onDidSaveTextDocument((doc) => {
        if (!this.active || doc.uri.scheme !== "file") return;
        const rel = this.relPathForFs(doc.uri.fsPath);
        if (!rel || this.isSuppressed(rel)) return;
        const oldTimer = this.changeTimers.get(rel);
        if (oldTimer) clearTimeout(oldTimer);
        this.changeTimers.delete(rel);
        this.broadcast({ type: "upsert", path: rel, content: doc.getText() });
      })
    );

    const root = this.getRoot();
    if (root) {
      const fsw = vscode.workspace.createFileSystemWatcher("**/*");
      const sendDisk = (uri) => {
        const rel = this.relPathForFs(uri.fsPath);
        if (!rel || this.isSuppressed(rel)) return;
        try {
          const st = fs.lstatSync(uri.fsPath);
          if (!st.isSymbolicLink() && st.isFile() && st.size <= 512 * 1024) {
            const buf = fs.readFileSync(uri.fsPath);
            if (isTextBuffer(buf)) this.broadcast({ type: "upsert", path: rel, content: buf.toString("utf8") });
          }
        } catch {}
      };
      fsw.onDidCreate(sendDisk);
      fsw.onDidChange(sendDisk);
      fsw.onDidDelete((uri) => {
        const rel = this.relPathForFs(uri.fsPath);
        if (rel && !this.isSuppressed(rel)) {
          this.broadcast({ type: "delete", path: rel, isDir: false });
        }
      });
      this.disposables.push(fsw);
    }
  }

  disposeWatchers() {
    for (const t of this.changeTimers.values()) clearTimeout(t);
    this.changeTimers.clear();
    while (this.disposables.length > 0) {
      try { this.disposables.pop().dispose(); } catch {}
    }
  }

  async start(options = {}) {
    if (!this.permanentKey) {
      this.permanentKey = (await this.context.secrets.get(SECRET_STORAGE_KEY)) || "";
    }
    if (!this.permanentKey) {
      this.permanentKey = randomPermanentKey();
      await this.context.secrets.store(SECRET_STORAGE_KEY, this.permanentKey);
    }
    this.quickPin = options.withPin ? randomPin6() : "";
    this.active = true;
    this.stopRelayWorkers();
    this.startLanServer();
    const wPerm = this.spawnRelayWorker(this.permanentKey, false);
    if (wPerm) this.relayWorkers.push(wPerm);
    if (this.quickPin) {
      const wPin = this.spawnRelayWorker(this.quickPin, true);
      if (wPin) this.relayWorkers.push(wPin);
    }
    this.installWatchers();
    this.updateStatusBar();
  }

  stop() {
    this.active = false;
    this.quickPin = "";
    this.stopRelayWorkers();
    this.stopLanServer();
    this.disposeWatchers();
    this.updateStatusBar();
  }

  async showQuickPin() {
    await this.start({ withPin: true });
    const choice = await vscode.window.showInformationMessage(
      `3012 Sync PIN 6 số: ${this.quickPin} (Relay: ${this.relayUrl()})`,
      "Sao chép PIN",
      "Sao chép Khóa Vĩnh Viễn"
    );
    if (choice === "Sao chép PIN") {
      await vscode.env.clipboard.writeText(this.quickPin);
    } else if (choice === "Sao chép Khóa Vĩnh Viễn") {
      await vscode.env.clipboard.writeText(this.permanentKey);
    }
  }

  async setPermanentKeyFlow() {
    const existing = (await this.context.secrets.get(SECRET_STORAGE_KEY)) || this.permanentKey || "";
    const entered = await vscode.window.showInputBox({
      title: "3012 Sync — Khóa Đồng Bộ Vĩnh Viễn",
      prompt: "Dán Khóa Vĩnh Viễn chung với 3012 iOS (để trống để tự tạo khóa mới)",
      value: existing,
      ignoreFocusOut: true
    });
    if (entered === undefined) return;
    const clean = entered.trim() || randomPermanentKey();
    this.permanentKey = clean;
    await this.context.secrets.store(SECRET_STORAGE_KEY, clean);
    await this.start({ withPin: false });
    await vscode.env.clipboard.writeText(clean);
    vscode.window.showInformationMessage(`3012 Sync đã lưu & sao chép Khóa Vĩnh Viễn (${clean}).`);
  }

  async showMenu() {
    const perm = (await this.context.secrets.get(SECRET_STORAGE_KEY)) || this.permanentKey || "(chưa tạo)";
    const items = [
      {
        label: "$(key) Hiện mã PIN 6 số ghép nối nhanh 1 lần",
        description: this.quickPin ? `Đang mở PIN: ${this.quickPin}` : "Tạo PIN 6 số tạm -> tự nhớ Khóa Vĩnh Viễn",
        action: "pin"
      },
      {
        label: "$(lock) Nhập / Tạo Khóa Đồng Bộ Vĩnh Viễn",
        description: perm,
        action: "key"
      },
      {
        label: "$(link) Sao chép Link Ghép Đôi 1 chạm (3012sync://)",
        description: "Mở trên iPhone để lưu tự động",
        action: "deeplink"
      },
      {
        label: "$(cloud-upload) Đẩy toàn bộ Workspace sang iPhone ngay",
        description: "Đồng bộ snapshot mới nhất",
        action: "push"
      },
      {
        label: this.active ? "$(debug-disconnect) Ngắt kết nối 3012 Sync" : "$(plug) Kết nối lại 3012 Sync",
        description: this.relayUrl(),
        action: this.active ? "stop" : "start"
      }
    ];
    const picked = await vscode.window.showQuickPick(items, { placeHolder: "3012 Mobile IDE Sync — Chọn thao tác" });
    if (!picked) return;
    if (picked.action === "pin") {
      await this.showQuickPin();
    } else if (picked.action === "key") {
      await this.setPermanentKeyFlow();
    } else if (picked.action === "deeplink") {
      if (!this.active) await this.start({ withPin: false });
      const url = `3012sync://pair?relay=${encodeURIComponent(this.relayUrl())}&key=${encodeURIComponent(this.permanentKey)}`;
      await vscode.env.clipboard.writeText(url);
      vscode.window.showInformationMessage("Đã sao chép link ghép đôi 3012sync:// vào Clipboard.");
    } else if (picked.action === "push") {
      if (!this.active) await this.start({ withPin: false });
      const snap = this.collectSnapshot();
      this.broadcast({ type: "snapshot", files: snap });
      vscode.window.showInformationMessage(`Đã đẩy ${Object.keys(snap).length} file sang 3012.`);
    } else if (picked.action === "stop") {
      this.stop();
    } else if (picked.action === "start") {
      await this.start({ withPin: false });
    }
  }
}

let controller = null;

async function activate(context) {
  controller = new SyncController(context);
  context.subscriptions.push(
    controller.statusBar,
    controller.output,
    vscode.commands.registerCommand("3012sync.menu", () => controller.showMenu()),
    vscode.commands.registerCommand("3012sync.quickPairPin", () => controller.showQuickPin()),
    vscode.commands.registerCommand("3012sync.setPermanentKey", () => controller.setPermanentKeyFlow()),
    vscode.commands.registerCommand("3012sync.pushSnapshot", async () => {
      if (!controller.active) await controller.start({ withPin: false });
      const snap = controller.collectSnapshot();
      controller.broadcast({ type: "snapshot", files: snap });
    }),
    vscode.commands.registerCommand("3012sync.disconnect", () => controller.stop())
  );

  const savedKey = await context.secrets.get(SECRET_STORAGE_KEY);
  const autoConnect = vscode.workspace.getConfiguration("3012sync").get("autoConnectOnStartup", true);
  if (autoConnect && savedKey) {
    controller.permanentKey = savedKey;
    await controller.start({ withPin: false });
  } else {
    controller.updateStatusBar();
  }
}

function deactivate() {
  if (controller) controller.stop();
}

module.exports = { activate, deactivate };
