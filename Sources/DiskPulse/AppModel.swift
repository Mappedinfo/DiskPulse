import AppKit
import Combine
import DiskPulseCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var samples: [DiskSample] = []
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    @Published private(set) var nextRecord: Date?
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published var paused = UserDefaults.standard.bool(forKey: "paused") {
        didSet {
            UserDefaults.standard.set(paused, forKey: "paused")
            timer?.invalidate()
            nextRecord = nil
            changed?()
            if !paused { Task { await refresh(record: true, force: true) } }
        }
    }
    @Published var showPercentage = UserDefaults.standard.object(forKey: "showPercentage") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPercentage, forKey: "showPercentage"); changed?() }
    }
    @Published var animations = UserDefaults.standard.object(forKey: "animations") as? Bool ?? true {
        didSet { UserDefaults.standard.set(animations, forKey: "animations"); changed?() }
    }

    var changed: (() -> Void)?
    var recorded: (() -> Void)?
    var latest: DiskSample? { samples.last }
    private let recorder = Recorder()
    private var timer: Timer?

    func start() {
        refreshLoginStatus()
        Task {
            // 先展示已有记录；当前磁盘读取失败时仍保留可用的历史。
            await refresh(record: false)
            if !paused { await refresh(record: true, force: true) }
        }
    }

    func refresh(record: Bool, force: Bool = false) async {
        guard !isRecording else { return }
        isRecording = true
        defer {
            isRecording = false
            schedule(retry: errorMessage != nil)
            changed?()
        }
        do {
            if record && !paused {
                let sample = try await recorder.capture(force: force)
                if sample != nil { recorded?() }
            }
            samples = try await recorder.history()
            errorMessage = nil
            notice = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func recordNow() {
        // 暂停只关闭自动采样，手动记录始终可用。
        Task {
            guard !isRecording else { return }
            isRecording = true
            defer { isRecording = false; schedule(retry: errorMessage != nil); changed?() }
            do {
                try await recorder.capture(force: true)
                samples = try await recorder.history()
                errorMessage = nil
                notice = "已更新本小时的记录"
                recorded?()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func clockOrWakeChanged() {
        timer?.invalidate()
        refreshLoginStatus()
        Task { await refresh(record: !paused, force: true) }
    }

    func stopTimer() { timer?.invalidate() }

    private func schedule(retry: Bool) {
        timer?.invalidate()
        guard !paused else { nextRecord = nil; return }
        let now = Date()
        let boundary = HourlySchedule.next(after: now).addingTimeInterval(1)
        let next = retry ? min(boundary, now.addingTimeInterval(300)) : boundary
        nextRecord = next
        let newTimer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refresh(record: true) }
        }
        newTimer.tolerance = 20
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = "无法更改登录启动：\(error.localizedDescription)" }
        refreshLoginStatus()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func showHistoryFolder() {
        NSWorkspace.shared.open(Recorder.defaultDirectory)
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "DiskPulse-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        panel.title = "导出全部容量记录"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await self.recorder.export(to: url)
                    self.notice = "已导出：\(url.lastPathComponent)"
                    self.errorMessage = nil
                } catch { self.errorMessage = error.localizedDescription }
            }
        }
    }
}
