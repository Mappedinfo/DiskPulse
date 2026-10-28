import Charts
import DiskPulseCore
import SwiftUI

private let accent = Color(red: 0.06, green: 0.48, blue: 0.43)

@MainActor
struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var days = 7
    @State private var showSettings = false
    @State private var metric: HistoryMetric = .estimatedUsed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visible: [DiskSample] {
        let start = Date().addingTimeInterval(-Double(days) * 86_400)
        return model.samples.filter { $0.date >= start && metric.bytes(for: $0) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            header
            if let sample = model.latest { capacity(sample) }
            else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isRecording ? "正在读取磁盘容量…" : "你的第一条容量记录")
                        .font(.title3.weight(.semibold))
                    Text("开始记录后，这里会显示磁盘用量和变化。")
                        .foregroundStyle(.secondary)
                }.frame(height: 105, alignment: .leading)
            }
            history
            status
            HStack(spacing: 10) {
                Button(action: model.recordNow) {
                    Label(model.isRecording ? "记录中" : "记录一次", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(accent)
                .disabled(model.isRecording)
                Button { model.paused.toggle() } label: {
                    Label(model.paused ? "继续记录" : "暂停", systemImage: model.paused ? "play.fill" : "pause.fill")
                }.buttonStyle(.bordered)
            }.controlSize(.large)
            settings
            Divider()
            HStack {
                Label("仅保存在这台 Mac", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("退出后停止记录，历史保留")
            }.font(.system(size: 12))
        }
        .padding(22)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 22)).foregroundStyle(accent)
                .symbolEffect(.bounce, options: .nonRepeating,
                              value: model.animations && !reduceMotion ? model.latest?.date : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text("DiskPulse").font(.system(size: 17, weight: .bold, design: .rounded))
                Text("磁盘用量日记").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.paused ? "已暂停" : model.errorMessage == nil ? "每小时记录" : "需要重试")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(accent.opacity(0.09), in: Capsule())
        }
    }

    private func capacity(_ sample: DiskSample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(sample.availableBytes == nil ? "物理占用" : "已使用（估算）")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text(CapacityFormat.bytes(sample.usedBytes))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Text("可用 \(CapacityFormat.bytes(sample.displayAvailableBytes))")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text("总容量 \(CapacityFormat.bytes(sample.totalBytes))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(accent.opacity(0.1), lineWidth: 9)
                Circle().trim(from: 0, to: sample.fraction)
                    .stroke(sample.fraction > 0.9 ? Color.orange : accent,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(sample.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 82, height: 82)
            .accessibilityLabel("磁盘占用 \(sample.fraction.formatted(.percent))")
        }.padding(.vertical, 4)
            DisclosureGroup("容量明细") {
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("物理占用", value: CapacityFormat.bytes(sample.physicalUsedBytes))
                    LabeledContent("纯空闲", value: CapacityFormat.bytes(sample.freeBytes))
                    if let reclaimable = sample.estimatedReclaimableBytes {
                        LabeledContent("可回收估算", value: CapacityFormat.bytes(reclaimable))
                        Text("可用空间含系统可回收空间；已用为总容量减可用估算，可能与系统设置的刷新值略有差异。")
                    } else {
                        Text("此记录没有系统可用空间估算，当前显示物理占用。")
                    }
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.system(size: 12))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("统计口径", selection: $metric) {
                    ForEach(HistoryMetric.allCases) { item in Text(item.title).tag(item) }
                }.pickerStyle(.menu).labelsHidden().fixedSize()
                Spacer()
                if let first = visible.first, let last = visible.last, visible.count > 1 {
                    Text("区间 \(CapacityFormat.change(metric.bytes(for: last)! - metric.bytes(for: first)!))")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Picker("时间范围", selection: $days) {
                Text("24 小时").tag(1)
                Text("7 天").tag(7)
                Text("30 天").tag(30)
            }.pickerStyle(.segmented).labelsHidden()

            if visible.isEmpty {
                Text("这个时间段还没有记录")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                Chart(HistoryPoint.make(from: visible, metric: metric)) { point in
                    LineMark(
                        x: .value("时间", point.sample.date),
                        y: .value("容量 GB", Double(point.bytes) / 1_000_000_000),
                        series: .value("连续记录", point.segment)
                    ).foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("时间", point.sample.date),
                              y: .value("容量 GB", Double(point.bytes) / 1_000_000_000))
                        .foregroundStyle(accent).symbolSize(visible.count < 3 ? 30 : 8)
                }
                .chartXScale(domain: Date().addingTimeInterval(-Double(days) * 86_400)...Date())
                .chartYScale(domain: yDomain)
                .chartYAxisLabel("GB", position: .top, alignment: .trailing)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel(format: days == 1 ? .dateTime.hour().minute() : .dateTime.month().day())
                    }
                }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                .frame(height: 130)
                .accessibilityLabel("过去 \(days) 天的\(metric.title)，\(visible.count) 条记录，单位 GB")
            }
            Text(visible.count < 2 ? "每小时留一条记录，趋势会慢慢长出来。" : "\(visible.count) 条小时记录 · 休眠或退出期间留空")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if metric == .estimatedUsed && model.samples.contains(where: { $0.availableBytes == nil }) {
                Text("旧记录仅有物理占用，可切换上方口径查看。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = visible.compactMap { metric.bytes(for: $0).map { Double($0) / 1_000_000_000 } }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max(1, (high - low) * 0.2)
        return max(0, low - padding)...(high + padding)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if let notice = model.notice {
                Text(notice).foregroundStyle(accent)
            }
            if let latest = model.latest {
                Text("上次记录 \(latest.date.formatted(date: .abbreviated, time: .shortened))")
            }
            if model.paused { Text("自动记录已暂停，仍可手动记录。") }
            else if let next = model.nextRecord {
                Text("下次 \(next.formatted(date: .omitted, time: .shortened)) · 唤醒后自动恢复")
            }
        }.font(.system(size: 12)).foregroundStyle(.secondary)
    }

    private var settings: some View {
        DisclosureGroup("偏好设置", isExpanded: $showSettings) {
            VStack(spacing: 12) {
                Toggle("登录后自动启动", isOn: Binding(
                    get: { model.loginEnabled || model.loginNeedsApproval },
                    set: model.setLoginEnabled
                ))
                if model.loginNeedsApproval {
                    Button("在系统设置中允许登录启动", action: model.openLoginSettings)
                }
                Toggle("菜单栏显示占用比例", isOn: $model.showPercentage)
                Toggle("记录时播放小动画", isOn: $model.animations)
                HStack {
                    Button("导出 CSV…", action: model.exportCSV)
                    Spacer()
                    Button("打开记录文件夹", action: model.showHistoryFolder)
                }
            }.toggleStyle(.switch).controlSize(.small).padding(.top, 12)
        }.font(.system(size: 13))
    }
}
