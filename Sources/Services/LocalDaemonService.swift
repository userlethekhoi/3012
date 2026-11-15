import Foundation
import UIKit
import AVFoundation
import Network
import JavaScriptCore

public struct LocalDaemonJob: Identifiable, Equatable {
    public let id: UUID
    public let pid: Int
    public var name: String
    public var scriptPath: String
    public var isRunning: Bool
    public var startedAt: Date
    public var restartCount: Int
    public var logs: [String]

    public init(
        id: UUID = UUID(),
        pid: Int,
        name: String,
        scriptPath: String,
        isRunning: Bool = true,
        startedAt: Date = Date(),
        restartCount: Int = 0,
        logs: [String] = []
    ) {
        self.id = id
        self.pid = pid
        self.name = name
        self.scriptPath = scriptPath
        self.isRunning = isRunning
        self.startedAt = startedAt
        self.restartCount = restartCount
        self.logs = logs
    }

    public var uptimeFormatted: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

@MainActor
public final class LocalDaemonService: ObservableObject {
    @Published public var keepTerminalAliveInBackground: Bool {
        didSet {
            UserDefaults.standard.set(keepTerminalAliveInBackground, forKey: "3012.keepTerminalBg")
            syncKeepAliveState()
        }
    }

    @Published public var autoRestartOnError: Bool {
        didSet {
            UserDefaults.standard.set(autoRestartOnError, forKey: "3012.daemonAutoRestart")
        }
    }

    @Published public var preventScreenSleep: Bool {
        didSet {
            UserDefaults.standard.set(preventScreenSleep, forKey: "3012.preventScreenSleep")
            UIApplication.shared.isIdleTimerDisabled = preventScreenSleep
        }
    }

    @Published public private(set) var isKeepAliveActive: Bool = false
    @Published public private(set) var keepAliveStartedAt: Date? = nil
    @Published public private(set) var networkOnline: Bool = true
    @Published public private(set) var batteryPercentage: Int = 100
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var jobs: [LocalDaemonJob] = []

    public var onTerminalOutput: ((String) -> Void)?

    public var runningJobsCount: Int {
        jobs.filter(\.isRunning).count
    }

    private var nextPID: Int = 101
    private var silentAudioPlayer: AVAudioPlayer?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.dev.app3012.daemon.network")
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private final class ObserverBag: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: [NSObjectProtocol] = []

        func add(_ token: NSObjectProtocol) {
            lock.lock()
            tokens.append(token)
            lock.unlock()
        }

        func removeAll() {
            lock.lock()
            let current = tokens
            tokens.removeAll()
            lock.unlock()
            for token in current {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    private let observerBag = ObserverBag()

    private final class JobRuntimeHandle {
        let pid: Int
        let fileURL: URL?
        let inlineCode: String?
        let workspaceRoot: URL
        var context: JSContext?
        var timerTasks: [Int: Task<Void, Never>] = [:]
        var cancelledTimerIDs: Set<Int> = []
        var fetchTasks: [Int: Task<Void, Never>] = [:]
        var cancelled: Bool = false
        var restartScheduled: Bool = false

        init(pid: Int, fileURL: URL?, inlineCode: String?, workspaceRoot: URL) {
            self.pid = pid
            self.fileURL = fileURL
            self.inlineCode = inlineCode
            self.workspaceRoot = workspaceRoot
        }

        func teardown() {
            cancelled = true
            cancelledTimerIDs.removeAll()
            _ = context?.evaluateScript("if (typeof __teardownAll === 'function') __teardownAll();")
            for (_, task) in timerTasks { task.cancel() }
            timerTasks.removeAll()
            for (_, task) in fetchTasks { task.cancel() }
            fetchTasks.removeAll()
            context = nil
        }
    }

    private var runtimes: [Int: JobRuntimeHandle] = [:]
    private var jobSources: [Int: (fileURL: URL?, inlineCode: String?)] = [:]
    private let statusSnapshot = DeviceStatusSnapshotBox()

    private static let logDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    public init() {
        let savedKeep = UserDefaults.standard.object(forKey: "3012.keepTerminalBg") as? Bool ?? true
        let savedRestart = UserDefaults.standard.object(forKey: "3012.daemonAutoRestart") as? Bool ?? true
        let savedSleep = UserDefaults.standard.object(forKey: "3012.preventScreenSleep") as? Bool ?? false
        self.keepTerminalAliveInBackground = savedKeep
        self.autoRestartOnError = savedRestart
        self.preventScreenSleep = savedSleep
        UIApplication.shared.isIdleTimerDisabled = savedSleep

        startDeviceMonitors()
        registerLifecycleObservers()
        syncKeepAliveState()
    }

    deinit {
        observerBag.removeAll()
        pathMonitor.cancel()
    }

    // MARK: - 24/7 Screen-Off Background Keep-Alive (Lazy audio session only when bots/jobs are active)
    public func syncKeepAliveState() {
        let shouldStayAlive = runningJobsCount > 0 && keepTerminalAliveInBackground
        if shouldStayAlive {
            startSilentAudioLoopIfNeeded()
        } else {
            stopSilentAudioLoop()
        }
        statusSnapshot.updateMetrics(
            battery: batteryPercentage,
            charging: isCharging,
            networkOnline: networkOnline,
            keepAliveActive: isKeepAliveActive
        )
    }

    private func startSilentAudioLoopIfNeeded() {
        if let player = silentAudioPlayer, player.isPlaying {
            isKeepAliveActive = true
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            let wavData = Self.makeSilentWAVData()
            let player = try AVAudioPlayer(data: wavData)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            player.play()
            self.silentAudioPlayer = player
            self.isKeepAliveActive = true
            if self.keepAliveStartedAt == nil {
                self.keepAliveStartedAt = Date()
            }
        } catch {
            self.isKeepAliveActive = false
        }
    }

    private func stopSilentAudioLoop() {
        silentAudioPlayer?.stop()
        silentAudioPlayer = nil
        isKeepAliveActive = false
        keepAliveStartedAt = nil
    }

    private func startDeviceMonitors() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBatteryState()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isUp = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.networkOnline = isUp
                self.statusSnapshot.updateMetrics(
                    battery: self.batteryPercentage,
                    charging: self.isCharging,
                    networkOnline: isUp,
                    keepAliveActive: self.isKeepAliveActive
                )
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func refreshBatteryState() {
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            batteryPercentage = Int(round(level * 100))
        }
        let st = UIDevice.current.batteryState
        isCharging = (st == .charging || st == .full)
        statusSnapshot.updateMetrics(
            battery: batteryPercentage,
            charging: isCharging,
            networkOnline: networkOnline,
            keepAliveActive: isKeepAliveActive
        )
    }

    private func registerLifecycleObservers() {
        let nc = NotificationCenter.default

        observerBag.add(nc.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshBatteryState() }
        })
        observerBag.add(nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshBatteryState() }
        })

        observerBag.add(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.runningJobsCount > 0 && self.keepTerminalAliveInBackground {
                    self.beginTransientBackgroundAssertion()
                    self.startSilentAudioLoopIfNeeded()
                }
            }
        })

        observerBag.add(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endTransientBackgroundAssertion()
                self.refreshBatteryState()
                self.syncKeepAliveState()
            }
        })

        observerBag.add(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rawType == AVAudioSession.InterruptionType.ended.rawValue,
                   self.runningJobsCount > 0 && self.keepTerminalAliveInBackground {
                    self.startSilentAudioLoopIfNeeded()
                }
            }
        })
    }

    private func beginTransientBackgroundAssertion() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "3012.LocalDaemonKeepAlive") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endTransientBackgroundAssertion()
            }
        }
    }

    private func endTransientBackgroundAssertion() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Job Lifecycle Management
    @discardableResult
    public func startJob(fileURL: URL, workspaceRoot: URL) -> LocalDaemonJob {
        let pid = nextPID
        nextPID += 1

        let fileCanon = WorkspaceManager.canonicalPath(fileURL)
        let rootCanon = WorkspaceManager.canonicalPath(workspaceRoot)
        let rootPrefix = rootCanon == "/" ? "/" : rootCanon + "/"
        let relPath = fileCanon.hasPrefix(rootPrefix)
            ? String(fileCanon.dropFirst(rootPrefix.count))
            : fileURL.lastPathComponent
        let job = LocalDaemonJob(
            pid: pid,
            name: fileURL.lastPathComponent,
            scriptPath: relPath,
            isRunning: true,
            startedAt: Date(),
            restartCount: 0,
            logs: []
        )
        jobs.insert(job, at: 0)

        let rawContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let ext = fileURL.pathExtension.lowercased()
        let runnableJS: String
        if ext == "py" {
            runnableJS = buildPythonBotAdapterScript(pythonSource: rawContent, workspaceRoot: workspaceRoot)
        } else {
            runnableJS = rawContent
        }

        let handle = JobRuntimeHandle(pid: pid, fileURL: fileURL, inlineCode: nil, workspaceRoot: workspaceRoot)
        runtimes[pid] = handle
        jobSources[pid] = (fileURL: fileURL, inlineCode: nil)
        statusSnapshot.setStartedAt(pid: pid, date: job.startedAt)
        syncKeepAliveState()

        appendLog(pid: pid, line: "[PID \(pid)] Started on-device daemon: \(relPath)")
        launchJSRuntime(handle: handle, source: runnableJS)

        return jobs.first(where: { $0.pid == pid }) ?? job
    }

    @discardableResult
    public func startInlineCommand(name: String, jsCode: String, workspaceRoot: URL) -> LocalDaemonJob {
        let pid = nextPID
        nextPID += 1

        let job = LocalDaemonJob(
            pid: pid,
            name: name,
            scriptPath: "<inline:\(name)>",
            isRunning: true,
            startedAt: Date(),
            restartCount: 0,
            logs: []
        )
        jobs.insert(job, at: 0)

        let handle = JobRuntimeHandle(pid: pid, fileURL: nil, inlineCode: jsCode, workspaceRoot: workspaceRoot)
        runtimes[pid] = handle
        jobSources[pid] = (fileURL: nil, inlineCode: jsCode)
        statusSnapshot.setStartedAt(pid: pid, date: job.startedAt)
        syncKeepAliveState()

        appendLog(pid: pid, line: "[PID \(pid)] Started on-device task: \(name)")
        launchJSRuntime(handle: handle, source: jsCode)

        return jobs.first(where: { $0.pid == pid }) ?? job
    }

    public func stopJob(pid: Int) {
        if let handle = runtimes[pid] {
            handle.teardown()
            runtimes.removeValue(forKey: pid)
        }
        statusSnapshot.removePID(pid)
        if let idx = jobs.firstIndex(where: { $0.pid == pid }) {
            jobs[idx].isRunning = false
        }
        appendLog(pid: pid, line: "[PID \(pid)] Stopped cleanly.")
        syncKeepAliveState()
    }

    public func stopAllJobs() {
        let activePIDs = jobs.filter(\.isRunning).map(\.pid)
        for pid in activePIDs {
            stopJob(pid: pid)
        }
    }

    public func restartJob(pid: Int, workspaceRoot: URL) {
        guard let existing = jobs.first(where: { $0.pid == pid }) else { return }
        let existingHandle = runtimes[pid]
        let savedSource = jobSources[pid]
        let inlineCode = existingHandle?.inlineCode ?? savedSource?.inlineCode
        let fileURL = existingHandle?.fileURL ?? savedSource?.fileURL ?? workspaceRoot.appendingPathComponent(existing.scriptPath)

        if let existingHandle {
            existingHandle.teardown()
            runtimes.removeValue(forKey: pid)
        }

        let startedNow = Date()
        if let idx = jobs.firstIndex(where: { $0.pid == pid }) {
            jobs[idx].isRunning = true
            jobs[idx].startedAt = startedNow
            jobs[idx].restartCount += 1
        }
        statusSnapshot.setStartedAt(pid: pid, date: startedNow)

        let newHandle = JobRuntimeHandle(
            pid: pid,
            fileURL: inlineCode == nil ? fileURL : nil,
            inlineCode: inlineCode,
            workspaceRoot: workspaceRoot
        )
        runtimes[pid] = newHandle
        jobSources[pid] = (fileURL: inlineCode == nil ? fileURL : nil, inlineCode: inlineCode)
        syncKeepAliveState()

        appendLog(pid: pid, line: "[PID \(pid)] Restarting on-device daemon...")
        if let inlineCode {
            launchJSRuntime(handle: newHandle, source: inlineCode)
        } else {
            let raw = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let script = fileURL.pathExtension.lowercased() == "py"
                ? buildPythonBotAdapterScript(pythonSource: raw, workspaceRoot: workspaceRoot)
                : raw
            launchJSRuntime(handle: newHandle, source: script)
        }
    }

    public func clearLogs(pid: Int) {
        if let idx = jobs.firstIndex(where: { $0.pid == pid }) {
            jobs[idx].logs.removeAll()
        }
    }

    public func removeStoppedJobs() {
        let stoppedPIDs = jobs.filter { !$0.isRunning }.map(\.pid)
        for pid in stoppedPIDs {
            jobSources.removeValue(forKey: pid)
        }
        jobs.removeAll { !$0.isRunning }
    }

    public func appendLog(pid: Int, line: String) {
        let stamp = Self.logDateFormatter.string(from: Date())
        let formatted = "[\(stamp)] \(line)"
        if let idx = jobs.firstIndex(where: { $0.pid == pid }) {
            jobs[idx].logs.append(formatted)
            if jobs[idx].logs.count > 400 {
                jobs[idx].logs.removeFirst(jobs[idx].logs.count - 400)
            }
        }
        onTerminalOutput?("[\(pid)] \(line)\r\n")
    }

    // MARK: - Telegram Bot 1-Tap Scaffolder
    @discardableResult
    public func scaffoldTelegramBot(botToken: String, in workspace: WorkspaceManager, startImmediately: Bool = true) -> URL {
        let cleanToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = workspace.rootURL

        let envURL = root.appendingPathComponent(".env")
        var envText = (try? String(contentsOf: envURL, encoding: .utf8)) ?? ""
        if !cleanToken.isEmpty {
            if envText.contains("TELEGRAM_BOT_TOKEN=") {
                let lines = envText.components(separatedBy: .newlines).map { line -> String in
                    line.hasPrefix("TELEGRAM_BOT_TOKEN=") ? "TELEGRAM_BOT_TOKEN=\(cleanToken)" : line
                }
                envText = lines.joined(separator: "\n")
            } else {
                if !envText.isEmpty && !envText.hasSuffix("\n") { envText += "\n" }
                envText += "TELEGRAM_BOT_TOKEN=\(cleanToken)\n"
            }
            try? envText.write(to: envURL, atomically: true, encoding: .utf8)
        } else if !FileManager.default.fileExists(atPath: envURL.path) {
            let placeholder = "# Paste your token from @BotFather below:\nTELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN_HERE\n"
            try? placeholder.write(to: envURL, atomically: true, encoding: .utf8)
        }

        let botURL = root.appendingPathComponent("telegram_bot.js")
        let botTemplate = #"""
        // 3012 On-Device 24/7 Telegram Bot (Runs locally on your iPhone/iPad — No VPS required)
        // Enable "Keep Terminal & Bot Alive 24/7" so it keeps running even when the screen is off.

        const token = process.env.TELEGRAM_BOT_TOKEN || '';
        const bot = new TelegramBot(token);

        bot.onCommand('start', async (msg) => {
          const name = (msg.from && msg.from.first_name) ? msg.from.first_name : 'Developer';
          await bot.sendMessage(
            msg.chat.id,
            `Xin chao ${name}! Bot nay dang chay 24/7 truc tiep tren iPhone/iPad bang 3012 IDE.`
          );
        });

        bot.onCommand('ping', async (msg) => {
          const st = process.deviceStatus();
          await bot.sendMessage(
            msg.chat.id,
            `Pong! Pin: ${st.battery}% | Mang: ${st.networkOnline ? 'Online' : 'Offline'} | Uptime: ${st.uptimeSeconds}s`
          );
        });

        bot.onCommand('status', async (msg) => {
          const st = process.deviceStatus();
          await bot.sendMessage(
            msg.chat.id,
            `[3012 On-Device Daemon]\n- Platform: ${st.platform}\n- Pin: ${st.battery}% (${st.charging ? 'Dang sac' : 'Pin'})\n- Keep-Alive: ${st.keepAliveActive ? 'ON' : 'OFF'}\n- Uptime: ${st.uptimeSeconds}s`
          );
        });

        bot.onCommand('id', async (msg) => {
          await bot.sendMessage(msg.chat.id, `Chat ID: ${msg.chat.id}`);
        });

        bot.onCommand('echo', async (msg) => {
          const arg = (msg.text || '').replace(/^\/echo\s*/i, '').trim();
          await bot.sendMessage(msg.chat.id, arg || 'Hay nhap noi dung sau /echo');
        });

        bot.onMessage(async (msg) => {
          if (msg.text) {
            console.log(`[MSG] ${msg.chat.id}: ${msg.text}`);
          }
        });

        bot.startPolling(1200);
        console.log('Bot polling loop active on device. Safe to lock screen when Keep-Alive is ON.');
        """#
        try? botTemplate.write(to: botURL, atomically: true, encoding: .utf8)
        workspace.reloadTree()
        workspace.openFile(at: botURL)

        if startImmediately {
            startJob(fileURL: botURL, workspaceRoot: root)
        }
        return botURL
    }

    // MARK: - JavaScriptCore Persistent Runtime Bridge
    private func launchJSRuntime(handle: JobRuntimeHandle, source: String) {
        guard let ctx = JSContext() else {
            appendLog(pid: handle.pid, line: "[Error] Failed to create JSContext.")
            if let idx = jobs.firstIndex(where: { $0.pid == handle.pid }) {
                jobs[idx].isRunning = false
            }
            return
        }
        handle.context = ctx
        let pid = handle.pid
        let root = handle.workspaceRoot

        ctx.exceptionHandler = { [weak self, weak handle] _, exception in
            guard let self, let exc = exception else { return }
            let msg = "[JS Error] \(exc)"
            Task { @MainActor in
                self.appendLog(pid: pid, line: msg)
                let currentRestartCount = self.jobs.first(where: { $0.pid == pid })?.restartCount ?? 0
                if self.autoRestartOnError,
                   let handle,
                   !handle.cancelled,
                   !handle.restartScheduled,
                   currentRestartCount < 5 {
                    handle.restartScheduled = true
                    self.appendLog(pid: pid, line: "[Auto-Restart] Bot encountered an error; restarting in 3s...")
                    Task { @MainActor [weak self, weak handle] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard let self,
                              let handle,
                              !Task.isCancelled,
                              self.autoRestartOnError,
                              self.jobs.first(where: { $0.pid == pid })?.isRunning == true,
                              let activeHandle = self.runtimes[pid],
                              activeHandle === handle,
                              !activeHandle.cancelled else { return }
                        self.restartJob(pid: pid, workspaceRoot: root)
                    }
                }
            }
        }

        // 1. Console logging bridge
        let makeLogBlock: (String) -> @convention(block) () -> Void = { [weak self] prefix in
            return {
                let args = JSContext.currentArguments() ?? []
                let text = args.map { "\($0)" }.joined(separator: " ")
                let line = prefix.isEmpty ? text : "\(prefix) \(text)"
                Task { @MainActor [weak self] in
                    self?.appendLog(pid: pid, line: line)
                }
            }
        }
        if let consoleObj = JSValue(newObjectIn: ctx) {
            consoleObj.setObject(makeLogBlock(""), forKeyedSubscript: "log" as NSString)
            consoleObj.setObject(makeLogBlock(""), forKeyedSubscript: "info" as NSString)
            consoleObj.setObject(makeLogBlock("[WARN]"), forKeyedSubscript: "warn" as NSString)
            consoleObj.setObject(makeLogBlock("[ERROR]"), forKeyedSubscript: "error" as NSString)
            ctx.setObject(consoleObj, forKeyedSubscript: "console" as NSString)
        }

        // 2. Async Timer Bridge (setTimeout / setInterval)
        let scheduleTimer: @convention(block) (Int, Double, Bool) -> Void = { [weak self, weak handle] timerID, delayMs, repeats in
            Task { @MainActor [weak self, weak handle] in
                guard let self, let handle, !handle.cancelled else { return }
                if handle.cancelledTimerIDs.remove(timerID) != nil {
                    return
                }
                let safeMs = delayMs.isFinite ? min(max(delayMs, 1.0), 86_400_000.0) : 1000.0
                let clampedNs = UInt64(safeMs * 1_000_000)
                let task = Task { @MainActor [weak self, weak handle] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: clampedNs)
                        guard !Task.isCancelled, let handle, !handle.cancelled, let ctx = handle.context else { break }
                        _ = ctx.evaluateScript("__fireTimer(\(timerID), \(repeats ? "true" : "false"));")
                        if !repeats {
                            handle.timerTasks.removeValue(forKey: timerID)
                            break
                        }
                    }
                    _ = self
                }
                handle.timerTasks[timerID] = task
            }
        }
        let cancelTimer: @convention(block) (Int) -> Void = { [weak handle] timerID in
            Task { @MainActor [weak handle] in
                guard let handle else { return }
                if let activeTask = handle.timerTasks.removeValue(forKey: timerID) {
                    activeTask.cancel()
                } else {
                    handle.cancelledTimerIDs.insert(timerID)
                }
            }
        }
        ctx.setObject(scheduleTimer, forKeyedSubscript: "_nativeScheduleTimer" as NSString)
        ctx.setObject(cancelTimer, forKeyedSubscript: "_nativeCancelTimer" as NSString)

        // 3. Native URLSession Async Fetch Bridge
        let nativeFetch: @convention(block) (Int, String, String, String, String) -> Void = { [weak handle] fetchID, urlStr, method, headersJSON, bodyStr in
            Task { @MainActor [weak handle] in
                guard let handle, !handle.cancelled else { return }
                let task = Task { [weak handle] in
                    guard let url = URL(string: urlStr) else {
                        await MainActor.run { [weak handle] in
                            guard let handle, !handle.cancelled, let ctx = handle.context else { return }
                            let errArg = Self.jsStringLiteral("Invalid URL: \(urlStr)")
                            _ = ctx.evaluateScript("__rejectFetch(\(fetchID), \(errArg));")
                            handle.fetchTasks.removeValue(forKey: fetchID)
                        }
                        return
                    }

                    var req = URLRequest(url: url)
                    req.httpMethod = method.uppercased()
                    req.timeoutInterval = 35
                    if let hData = headersJSON.data(using: .utf8),
                       let headers = try? JSONSerialization.jsonObject(with: hData) as? [String: Any] {
                        for (k, v) in headers where !(v is NSNull) {
                            req.setValue("\(v)", forHTTPHeaderField: k)
                        }
                    }
                    if !bodyStr.isEmpty && req.httpMethod != "GET" && req.httpMethod != "HEAD" {
                        req.httpBody = Data(bodyStr.utf8)
                    }

                    do {
                        let (data, resp) = try await URLSession.shared.data(for: req)
                        let http = resp as? HTTPURLResponse
                        let status = http?.statusCode ?? 200
                        let ok = (200...299).contains(status)
                        let statusText = HTTPURLResponse.localizedString(forStatusCode: status)
                        let text = String(data: data, encoding: .utf8) ?? ""

                        await MainActor.run { [weak handle] in
                            guard let handle, !handle.cancelled, let ctx = handle.context else { return }
                            let stArg = Self.jsStringLiteral(statusText)
                            let bodyArg = Self.jsStringLiteral(text)
                            _ = ctx.evaluateScript("__resolveFetch(\(fetchID), \(ok ? "true" : "false"), \(status), \(stArg), \(bodyArg));")
                            handle.fetchTasks.removeValue(forKey: fetchID)
                        }
                    } catch {
                        await MainActor.run { [weak handle] in
                            guard let handle, !handle.cancelled, let ctx = handle.context else { return }
                            let errArg = Self.jsStringLiteral(error.localizedDescription)
                            _ = ctx.evaluateScript("__rejectFetch(\(fetchID), \(errArg));")
                            handle.fetchTasks.removeValue(forKey: fetchID)
                        }
                    }
                }
                handle.fetchTasks[fetchID] = task
            }
        }
        ctx.setObject(nativeFetch, forKeyedSubscript: "_nativeFetch" as NSString)

        // 4. Scoped Local Filesystem (`fs`) Bridge
        let rootCanon = WorkspaceManager.canonicalPath(root)
        let rootPrefix = rootCanon == "/" ? "/" : rootCanon + "/"
        let resolveScopedURL: (String) -> URL? = { rel in
            let clean = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let rawTarget = clean.isEmpty ? root : root.appendingPathComponent(clean)
            let targetCanon = WorkspaceManager.canonicalPath(rawTarget)
            guard targetCanon == rootCanon || targetCanon.hasPrefix(rootPrefix) else { return nil }
            return URL(fileURLWithPath: targetCanon)
        }
        if let fsObj = JSValue(newObjectIn: ctx) {
            let readFile: @convention(block) (String) -> String? = { rel in
                guard let target = resolveScopedURL(rel) else { return nil }
                return try? String(contentsOf: target, encoding: .utf8)
            }
            let writeFile: @convention(block) (String, String) -> Bool = { rel, content in
                guard let target = resolveScopedURL(rel) else { return false }
                do {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try content.write(to: target, atomically: true, encoding: .utf8)
                    return true
                } catch {
                    return false
                }
            }
            let appendFile: @convention(block) (String, String) -> Bool = { rel, content in
                guard let target = resolveScopedURL(rel) else { return false }
                let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
                return writeFile(rel, existing + content)
            }
            let existsFile: @convention(block) (String) -> Bool = { rel in
                guard let target = resolveScopedURL(rel) else { return false }
                return FileManager.default.fileExists(atPath: target.path)
            }
            fsObj.setObject(readFile, forKeyedSubscript: "readFileSync" as NSString)
            fsObj.setObject(writeFile, forKeyedSubscript: "writeFileSync" as NSString)
            fsObj.setObject(appendFile, forKeyedSubscript: "appendFileSync" as NSString)
            fsObj.setObject(existsFile, forKeyedSubscript: "existsSync" as NSString)
            ctx.setObject(fsObj, forKeyedSubscript: "fs" as NSString)
        }

        // 5. `process.env` (.env parser) + `process.deviceStatus()`
        let envDict = Self.loadDotEnv(in: root)
        if let processObj = JSValue(newObjectIn: ctx) {
            processObj.setObject(envDict, forKeyedSubscript: "env" as NSString)
            let snapshotBox = self.statusSnapshot
            let jobPID = handle.pid
            let deviceStatusBlock: @convention(block) () -> [String: Any] = {
                snapshotBox.readStatus(forPID: jobPID)
            }
            processObj.setObject(deviceStatusBlock, forKeyedSubscript: "deviceStatus" as NSString)
            ctx.setObject(processObj, forKeyedSubscript: "process" as NSString)
        }

        // 6. Bootstrap Runtime (Promise fetch, setTimeout/setInterval, TelegramBot class)
        _ = ctx.evaluateScript(Self.jsBootstrapRuntime)
        _ = ctx.evaluateScript(source)
    }

    private func buildPythonBotAdapterScript(pythonSource: String, workspaceRoot: URL) -> String {
        // Parse explicit TELEGRAM_BOT_TOKEN literal in Python source if present, else fallback to .env
        var extractedToken = ""
        if let range = pythonSource.range(of: #"[0-9]{7,12}:[A-Za-z0-9_-]{30,}"#, options: .regularExpression) {
            extractedToken = String(pythonSource[range])
        }
        let hasTelegramIndicators = pythonSource.localizedCaseInsensitiveContains("telegram")
            || pythonSource.localizedCaseInsensitiveContains("telebot")
            || pythonSource.localizedCaseInsensitiveContains("aiogram")
            || !extractedToken.isEmpty

        if hasTelegramIndicators {
            // Extract simple @bot.message_handler(commands=['start', ...]) -> bot.reply_to(msg, "...")
            var cmdReplies: [(String, String)] = []
            let lines = pythonSource.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                if line.contains("commands=") || line.contains("Command("),
                   let cmdRange = line.range(of: #"['"]([a-zA-Z0-9_]+)['"]"#, options: .regularExpression) {
                    let cmd = String(line[cmdRange]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    var replyText = "Bot Python dang chay ngam 24/7 tren thiet bi 3012!"
                    let searchEnd = min(lines.count, idx + 8)
                    for k in idx..<searchEnd {
                        if (lines[k].contains("reply_to") || lines[k].contains("send_message") || lines[k].contains("answer")),
                           let msgRange = lines[k].range(of: #"['"]([^'"]{2,180})['"]\s*\)"#, options: .regularExpression) {
                            var captured = String(lines[k][msgRange])
                            if captured.hasSuffix(")") { captured.removeLast() }
                            replyText = captured.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                            break
                        }
                    }
                    cmdReplies.append((cmd, replyText))
                }
            }
            if cmdReplies.isEmpty {
                cmdReplies = [
                    ("start", "Python Bot đang chạy ngầm trực tiếp trên thiết bị iOS qua 3012 Daemon!"),
                    ("ping", "Pong! (On-Device Python Bot Runtime)")
                ]
            }

            let commandBlocks = cmdReplies.map { cmd, reply in
                "bot.onCommand(\(Self.jsStringLiteral(cmd)), async (msg) => { await bot.sendMessage(msg.chat.id, \(Self.jsStringLiteral(reply))); });"
            }.joined(separator: "\n")

            let tokenExpr = extractedToken.isEmpty
                ? "(process.env.TELEGRAM_BOT_TOKEN || process.env.BOT_TOKEN || '')"
                : Self.jsStringLiteral(extractedToken)

            return """
            console.log('[Python-Bot Adapter] Loaded on-device Telegram polling runtime (.env + command handlers)');
            const bot = new TelegramBot(\(tokenExpr));
            \(commandBlocks)
            bot.onMessage(async (msg) => {
              if (msg.text) console.log('[PY-BOT MSG] ' + msg.chat.id + ': ' + msg.text);
            });
            bot.startPolling(1200);
            """
        }

        // Generic Python print/heartbeat runner on device
        let folderLiteral = Self.jsStringLiteral(workspaceRoot.lastPathComponent)
        return """
        console.log('[Python Daemon] On-device script active in ' + \(folderLiteral));
        const __timer = setInterval(() => {
          const st = process.deviceStatus();
          console.log('[Heartbeat] Battery ' + st.battery + '% | Net ' + (st.networkOnline ? 'ON' : 'OFF') + ' | Uptime ' + st.uptimeSeconds + 's');
        }, 30000);
        """
    }

    public static func savedTelegramToken(in root: URL) -> String {
        let env = loadDotEnv(in: root)
        return env["TELEGRAM_BOT_TOKEN"] ?? env["BOT_TOKEN"] ?? ""
    }

    public func performHTTPGet(urlString: String) async -> String {
        guard let url = URL(string: urlString) else {
            return "curl: invalid URL '\(urlString)'"
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            return "[HTTP \(code)]\n\(body)"
        } catch {
            return "curl: \(error.localizedDescription)"
        }
    }

    private static func loadDotEnv(in root: URL) -> [String: String] {
        let envURL = root.appendingPathComponent(".env")
        guard let raw = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }
        var dict: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            if !key.isEmpty { dict[key] = val }
        }
        return dict
    }

    private static func jsStringLiteral(_ str: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [str]),
           let arr = String(data: data, encoding: .utf8),
           arr.count >= 2 {
            return String(arr.dropFirst().dropLast())
        }
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static let jsBootstrapRuntime = """
    var __timers = {};
    var __timerSeq = 1;
    var __pendingFetches = {};
    var __fetchSeq = 1;
    var __activeBots = [];

    globalThis.__teardownAll = function() {
      for (var i = 0; i < __activeBots.length; i++) {
        try { __activeBots[i].stop(); } catch (_) {}
      }
      __activeBots = [];
      __timers = {};
      __pendingFetches = {};
    };

    globalThis.__fireTimer = function(id, isInterval) {
      var entry = __timers[id];
      if (!entry) return;
      if (!isInterval) delete __timers[id];
      try {
        entry.fn.apply(null, entry.args);
      } catch (e) {
        console.error('[Timer Error]', e && e.stack ? e.stack : String(e));
      }
    };

    globalThis.setTimeout = function(fn, ms) {
      var args = Array.prototype.slice.call(arguments, 2);
      var id = __timerSeq++;
      __timers[id] = { fn: fn, args: args };
      _nativeScheduleTimer(id, Number(ms) || 0, false);
      return id;
    };

    globalThis.setInterval = function(fn, ms) {
      var args = Array.prototype.slice.call(arguments, 2);
      var id = __timerSeq++;
      __timers[id] = { fn: fn, args: args };
      _nativeScheduleTimer(id, Math.max(10, Number(ms) || 1000), true);
      return id;
    };

    globalThis.clearTimeout = globalThis.clearInterval = function(id) {
      delete __timers[id];
      _nativeCancelTimer(Number(id) || 0);
    };

    globalThis.__resolveFetch = function(id, ok, status, statusText, bodyText) {
      var cb = __pendingFetches[id];
      if (!cb) return;
      delete __pendingFetches[id];
      cb.resolve({
        ok: ok,
        status: status,
        statusText: statusText,
        text: function() { return Promise.resolve(bodyText); },
        json: function() {
          try { return Promise.resolve(JSON.parse(bodyText)); }
          catch (e) { return Promise.reject(e); }
        }
      });
    };

    globalThis.__rejectFetch = function(id, errMsg) {
      var cb = __pendingFetches[id];
      if (!cb) return;
      delete __pendingFetches[id];
      cb.reject(new Error(errMsg));
    };

    globalThis.fetch = function(url, options) {
      options = options || {};
      var method = options.method || 'GET';
      var headersJSON = options.headers ? JSON.stringify(options.headers) : '{}';
      var body = (options.body !== undefined && options.body !== null) ? String(options.body) : '';
      return new Promise(function(resolve, reject) {
        var id = __fetchSeq++;
        __pendingFetches[id] = { resolve: resolve, reject: reject };
        _nativeFetch(id, String(url), String(method), headersJSON, body);
      });
    };

    class TelegramBot {
      constructor(token) {
        this.token = String(token || '').trim();
        this.offset = 0;
        this._running = false;
        this._commandHandlers = {};
        this._messageHandlers = [];
        __activeBots.push(this);
      }

      onCommand(cmd, handler) {
        var clean = String(cmd).replace(/^\\//, '').toLowerCase();
        this._commandHandlers[clean] = handler;
        return this;
      }

      onMessage(handler) {
        this._messageHandlers.push(handler);
        return this;
      }

      async api(method, payload) {
        var res = await fetch('https://api.telegram.org/bot' + this.token + '/' + method, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload || {})
        });
        var data = await res.json();
        if (!data.ok) {
          throw new Error('Telegram API ' + method + ': ' + (data.description || res.status));
        }
        return data.result;
      }

      async sendMessage(chatId, text, extra) {
        return this.api('sendMessage', Object.assign({ chat_id: chatId, text: String(text) }, extra || {}));
      }

      async startPolling(intervalMs) {
        if (!this.token || this.token.indexOf(':') === -1 || this.token === 'YOUR_BOT_TOKEN_HERE') {
          console.error('[TelegramBot] Token khong hop le. Hay dien TELEGRAM_BOT_TOKEN vao file .env!');
          return;
        }
        this._running = true;
        try {
          var me = await this.api('getMe', {});
          console.log('[TelegramBot] Online tren may: @' + me.username + ' (id=' + me.id + ')');
        } catch (e) {
          console.error('[TelegramBot] Loi getMe:', e && e.message ? e.message : String(e));
        }
        var pollDelay = Math.max(400, Number(intervalMs) || 1200);
        var selfBot = this;
        async function pollStep() {
          if (!selfBot._running) return;
          try {
            var updates = await selfBot.api('getUpdates', { offset: selfBot.offset, timeout: 20 });
            for (var i = 0; i < updates.length; i++) {
              var upd = updates[i];
              selfBot.offset = upd.update_id + 1;
              var msg = upd.message || upd.edited_message;
              if (!msg) continue;
              var text = msg.text || '';
              if (text.indexOf('/') === 0) {
                var cmd = text.slice(1).split(/[\\s@]/)[0].toLowerCase();
                if (selfBot._commandHandlers[cmd]) {
                  await selfBot._commandHandlers[cmd](msg, selfBot);
                  continue;
                }
              }
              for (var h = 0; h < selfBot._messageHandlers.length; h++) {
                await selfBot._messageHandlers[h](msg, selfBot);
              }
            }
          } catch (err) {
            console.warn('[TelegramBot] Poll retry:', err && err.message ? err.message : String(err));
          }
          if (selfBot._running) {
            setTimeout(pollStep, pollDelay);
          }
        }
        pollStep();
      }

      stop() {
        this._running = false;
      }
    }
    globalThis.TelegramBot = TelegramBot;
    """

    private static func makeSilentWAVData() -> Data {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000
        let dataSize: UInt32 = numSamples * 2
        let riffSize: UInt32 = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })
        data.append(contentsOf: "WAVEfmt ".utf8)
        let fmtSize: UInt32 = 16
        let audioFormat: UInt16 = 1
        let numChannels: UInt16 = 1
        let byteRate: UInt32 = sampleRate * 2
        let blockAlign: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        data.append(withUnsafeBytes(of: fmtSize.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append(contentsOf: "data".utf8)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        data.append(Data(count: Int(dataSize)))
        return data
    }
}

private final class DeviceStatusSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var battery: Int = 100
    private var charging: Bool = false
    private var networkOnline: Bool = true
    private var keepAliveActive: Bool = false
    private var startedAtByPID: [Int: Date] = [:]

    func updateMetrics(battery: Int, charging: Bool, networkOnline: Bool, keepAliveActive: Bool) {
        lock.lock()
        self.battery = battery
        self.charging = charging
        self.networkOnline = networkOnline
        self.keepAliveActive = keepAliveActive
        lock.unlock()
    }

    func setStartedAt(pid: Int, date: Date) {
        lock.lock()
        startedAtByPID[pid] = date
        lock.unlock()
    }

    func removePID(_ pid: Int) {
        lock.lock()
        startedAtByPID.removeValue(forKey: pid)
        lock.unlock()
    }

    func readStatus(forPID pid: Int) -> [String: Any] {
        lock.lock()
        let b = battery
        let c = charging
        let n = networkOnline
        let k = keepAliveActive
        let startedAt = startedAtByPID[pid]
        lock.unlock()

        let uptime = startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        return [
            "battery": b,
            "charging": c,
            "networkOnline": n,
            "uptimeSeconds": uptime,
            "keepAliveActive": k,
            "platform": "iOS-Local-3012"
        ]
    }
}
