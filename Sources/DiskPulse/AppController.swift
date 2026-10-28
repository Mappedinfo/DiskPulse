import AppKit
import DiskPulseCore
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var pulseTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 即使从命令行重复运行，菜单栏也只保留一个实例。
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.imagePosition = .imageLeading
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))
        model.changed = { [weak self] in self?.updateStatus() }
        model.recorded = { [weak self] in self?.pulse() }
        updateStatus()
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.didWakeNotification) { [weak self] in
            self?.model.clockOrWakeChanged()
        }
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.willSleepNotification) { [weak self] in
            self?.model.stopTimer()
            self?.pulseTask?.cancel()
        }
        observe(NotificationCenter.default, name: .NSSystemClockDidChange) { [weak self] in
            self?.model.clockOrWakeChanged()
        }
        observe(NotificationCenter.default, name: .NSSystemTimeZoneDidChange) { [weak self] in
            self?.model.clockOrWakeChanged()
        }
        model.start()
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name,
                         action: @escaping @MainActor @Sendable () -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        })
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            model.refreshLoginStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            pulse()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        pulseTask?.cancel()
        updateStatus()
    }

    private func updateStatus(phase: Double? = nil) {
        guard let button = statusItem?.button else { return }
        let fraction = model.latest?.fraction ?? 0
        button.image = Self.icon(fraction: fraction, paused: model.paused, phase: phase)
        button.title = model.showPercentage
            ? (model.latest.map { " " + $0.fraction.formatted(.percent.precision(.fractionLength(0))) } ?? " —")
            : ""
        let value = model.latest.map {
            let label = $0.availableBytes == nil ? "物理占用" : "已用（估算）"
            return "\(label) \(CapacityFormat.bytes($0.usedBytes))，可用 \(CapacityFormat.bytes($0.displayAvailableBytes))"
        } ?? "等待第一条记录"
        button.toolTip = "DiskPulse · \(value)\(model.paused ? " · 已暂停" : "")"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func pulse() {
        pulseTask?.cancel()
        guard model.animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { updateStatus(); return }
        pulseTask = Task { [weak self] in
            for frame in 0..<24 {
                guard !Task.isCancelled else { return }
                self?.updateStatus(phase: Double(frame) / 24)
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            }
            self?.updateStatus()
        }
    }

    private static func icon(fraction: Double, paused: Bool, phase: Double?) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            let ring = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 14, height: 14))
            ring.lineWidth = 1.4
            NSColor.black.withAlphaComponent(0.22).setStroke()
            ring.stroke()
            let fill = NSBezierPath()
            fill.appendArc(withCenter: NSPoint(x: 10, y: 10), radius: 7,
                           startAngle: 90, endAngle: 90 - 360 * max(0.01, fraction), clockwise: true)
            fill.lineWidth = 2.1
            fill.lineCapStyle = .round
            NSColor.black.setStroke()
            fill.stroke()
            NSColor.black.setFill()
            if paused {
                NSBezierPath(rect: NSRect(x: 7.5, y: 7, width: 1.5, height: 6)).fill()
                NSBezierPath(rect: NSRect(x: 11, y: 7, width: 1.5, height: 6)).fill()
            } else if let phase {
                let angle = phase * 2 * .pi
                NSBezierPath(ovalIn: NSRect(x: 9 + cos(angle) * 4, y: 9 + sin(angle) * 4, width: 2, height: 2)).fill()
            } else {
                NSBezierPath(ovalIn: NSRect(x: 8.5, y: 8.5, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
