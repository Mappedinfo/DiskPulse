import AppKit
import DiskPulseCore
import Foundation

@main
enum DiskPulse {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") {
            print("""
                DiskPulse — 轻量 Mac 磁盘用量日记
                无参数：启动菜单栏应用
                --read：读取当前真实容量（JSON），不保存
                --sample：记录一次（JSON）
                --history：输出全部小时记录（CSV），不采样
                --data-dir PATH：指定测试或备份数据目录
                """)
            return
        }
        if arguments.contains("--read") || arguments.contains("--sample") || arguments.contains("--history") {
            Task { await runCommand(arguments) }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }

    private static func runCommand(_ arguments: [String]) async {
        do {
            let directory: URL
            if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
                directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            } else { directory = Recorder.defaultDirectory }
            let recorder = Recorder(directory: directory)
            if arguments.contains("--history") {
                print(CSVExport.text(try await recorder.history(since: .distantPast)), terminator: "")
            } else {
                let sample: DiskSample
                if arguments.contains("--sample") {
                    sample = try await recorder.capture(force: true)!
                } else { sample = try DiskReader.read() }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                print(String(decoding: try encoder.encode(sample), as: UTF8.self))
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}
