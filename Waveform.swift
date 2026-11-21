import AppKit
import SwiftUI

struct VCDTrace: Sendable {
    struct Signal: Identifiable, Sendable {
        let id: Int
        let code: String
        let name: String
        let width: Int
    }
    struct Change: Sendable {
        let time: Double
        let value: String
    }

    var signals: [Signal] = []
    var changes: [String: [Change]] = [:]
    var end = 0.0
    var scale = 1.0
    var unit = "ticks"
    var limited = false

    static func load(_ url: URL) throws -> Self {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // shortcut: preview a bounded prefix, use a streaming index for full-length large traces.
        let budget = 2 * 1024 * 1024
        var data = try file.read(upToCount: budget + 1) ?? Data()
        let truncated = data.count > budget
        if truncated {
            data = data.prefix(budget)
            if let space = data.lastIndex(where: { [9, 10, 13, 32].contains($0) }) {
                data.removeSubrange(space...)
            } else {
                data.removeAll()
            }
        }
        let tokens = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace)
        var trace = Self()
        trace.limited = truncated
        var scopes: [Substring] = []
        var i = 0
        var headerDone = false
        while i < tokens.count {
            guard let stop = tokens[i...].firstIndex(of: "$end") else { break }
            let fields = tokens[i..<stop]
            switch tokens[i] {
            case "$timescale":
                let scale = fields.dropFirst().joined()
                let digits = scale.prefix(while: \.isNumber)
                if let multiplier = Double(digits), !digits.isEmpty, digits.count < scale.count {
                    trace.scale = multiplier
                    trace.unit = String(scale.dropFirst(digits.count))
                }
            case "$scope" where fields.count >= 3:
                scopes.append(tokens[i + 2])
            case "$upscope":
                _ = scopes.popLast()
            case "$var" where fields.count >= 5:
                if let width = Int(tokens[i + 2]), width > 0,
                   !["real", "realtime", "string", "event"].contains(tokens[i + 1]) {
                    if trace.signals.count < 256 {
                        let code = String(tokens[i + 3])
                        let name = scopes.map(String.init) + [tokens[(i + 4)..<stop].joined(separator: " ")]
                        trace.signals.append(Signal(id: trace.signals.count, code: code,
                                                    name: name.joined(separator: "."), width: width))
                        trace.changes[code] = []
                    } else {
                        trace.limited = true
                    }
                }
            case "$enddefinitions":
                headerDone = true
            default: break
            }
            i = stop + 1
            if headerDone { break }
        }
        guard headerDone, !trace.signals.isEmpty else {
            throw NSError(domain: "VCD", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "No complete digital signal declarations were found in the first 2 MB. Reveal the VCD to inspect the file."])
        }
        var time = 0.0
        var count = 0
        while i < tokens.count {
            let token = tokens[i]
            i += 1
            guard let prefix = token.first else { continue }
            let code: String
            let value: String
            switch prefix {
            case "#":
                if let next = Double(token.dropFirst()), next.isFinite, next >= time {
                    time = next
                    trace.end = next
                }
                continue
            case "0", "1", "x", "X", "z", "Z":
                code = String(token.dropFirst())
                value = prefix.lowercased()
            case "b", "B":
                guard i < tokens.count else { continue }
                code = String(tokens[i])
                value = token.dropFirst().lowercased()
                i += 1
            case "r", "R", "s", "S":
                i = min(i + 1, tokens.count)
                continue
            case "$" where token == "$comment":
                i = tokens[i...].firstIndex(of: "$end").map { $0 + 1 } ?? tokens.count
                continue
            default: continue
            }
            guard trace.changes.keys.contains(code) else { continue }
            if trace.changes[code]?.last?.time == time {
                trace.changes[code]?.removeLast()
            }
            trace.changes[code]?.append(Change(time: time, value: value))
            count += 1
            if count == 100_000 { trace.limited = true; break }
        }
        return trace
    }

    func label(_ tick: Double) -> String {
        String(format: "%.7g %@", tick * scale, unit)
    }

    func value(for signal: Signal, at time: Double) -> String {
        guard let events = changes[signal.code] else { return "x" }
        var low = 0
        var high = events.count
        while low < high {
            let mid = (low + high) / 2
            if events[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? events[low - 1].value : "x"
    }
}

private final class WaveformSelection: ObservableObject {
    @Published var trace: VCDTrace?
    @Published var problem: String?
    @Published var cursor = 0.0
}

struct WaveformView: View {
    let url: URL
    @StateObject private var selection = WaveformSelection()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let trace = selection.trace {
                    Text("Cursor  \(trace.label((selection.cursor * trace.end).rounded()))")
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                Button("Reveal VCD") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if let trace = selection.trace {
                HStack(spacing: 10) {
                    Text("Signal").frame(width: 190, alignment: .leading)
                    Text(trace.label(0))
                    Spacer()
                    Text(trace.label(trace.end))
                }
                .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(trace.signals) { signal in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(signal.name).truncationMode(.head)
                                    Text(trace.value(for: signal, at: (selection.cursor * trace.end).rounded()))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.system(.caption, design: .monospaced)).lineLimit(1)
                                .frame(width: 190, alignment: .leading)
                                .help(signal.name)
                                GeometryReader { geometry in
                                    Canvas { ctx, size in
                                        draw(signal, in: trace, ctx: ctx, size: size)
                                    }
                                    .accessibilityHidden(true)
                                    .contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                                        selection.cursor = min(1, max(0, event.location.x / max(1, geometry.size.width)))
                                    })
                                }
                            }
                            .frame(height: 32)
                            Divider()
                        }
                    }
                }
                Slider(value: $selection.cursor, in: 0...1)
                    .accessibilityLabel("Time cursor")
                    .accessibilityValue(trace.label((selection.cursor * trace.end).rounded()))
                if trace.limited {
                    Text("Partial preview (2 MB, 256 signals, or 100,000 value changes). Reveal the VCD for the full trace.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let problem = selection.problem {
                Text(problem).foregroundStyle(.secondary)
            } else {
                ProgressView("Reading waveform…")
            }
        }
        .padding(12)
        .task(id: url) {
            selection.trace = nil
            selection.problem = nil
            selection.cursor = 0
            let result = await Task.detached(priority: .userInitiated) { [url] in
                Result { try VCDTrace.load(url) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let parsed): selection.trace = parsed
            case .failure(let error): selection.problem = error.localizedDescription
            }
        }
    }

    private func draw(_ signal: VCDTrace.Signal, in trace: VCDTrace, ctx: GraphicsContext, size: CGSize) {
        let high = 7.0
        let low = size.height - high
        var previousX = 0.0
        var previousValue = "x"
        func level(_ value: String) -> Double {
            switch value {
            case "1": return high
            case "0": return low
            default: return size.height / 2
            }
        }
        func segment(to x: Double) {
            let unknown = previousValue.contains("x") || previousValue.contains("z")
            let color: Color = unknown ? .orange : .teal
            var line = Path()
            if signal.width == 1 {
                line.move(to: CGPoint(x: previousX, y: level(previousValue)))
                line.addLine(to: CGPoint(x: x, y: level(previousValue)))
            } else {
                let bevel = min(3, (x - previousX) / 2)
                line.move(to: CGPoint(x: previousX, y: size.height / 2))
                for y in [high, low] {
                    line.addLine(to: CGPoint(x: previousX + bevel, y: y))
                    line.addLine(to: CGPoint(x: x - bevel, y: y))
                    line.addLine(to: CGPoint(x: x, y: size.height / 2))
                    line.move(to: CGPoint(x: previousX, y: size.height / 2))
                }
                if previousValue.count < 32, x - previousX > Double(previousValue.count) * 8 + 12 {
                    let text = Text(previousValue).font(.system(.caption2, design: .monospaced))
                    ctx.draw(text, at: CGPoint(x: (previousX + x) / 2, y: size.height / 2))
                }
            }
            ctx.stroke(line, with: .color(color), lineWidth: 1.4)
        }
        for event in trace.changes[signal.code] ?? [] {
            let x = event.time / max(trace.end, 1) * size.width
            segment(to: x)
            if signal.width == 1 {
                var edge = Path()
                edge.move(to: CGPoint(x: x, y: level(previousValue)))
                edge.addLine(to: CGPoint(x: x, y: level(event.value)))
                ctx.stroke(edge, with: .color(.teal))
            }
            previousValue = event.value
            previousX = x
        }
        segment(to: size.width)
        let x = trace.end > 0 ? (selection.cursor * trace.end).rounded() / trace.end * size.width : 0
        var marker = Path()
        marker.move(to: CGPoint(x: x, y: 0))
        marker.addLine(to: CGPoint(x: x, y: size.height))
        ctx.stroke(marker, with: .color(.primary.opacity(0.55)))
    }
}
