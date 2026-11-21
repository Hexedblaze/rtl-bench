import Foundation
import SwiftUI

@MainActor
final class Runs: ObservableObject {
    @Published var busy = false
    @Published var status = "Ready"
    @Published var console = ""
    @Published var output: URL?
    @Published var waveform: URL?
    private var engine: RTLEngine?

    func stop() {
        engine?.cancel()
        if busy { status = "Stopping…" }
    }

    func start(_ kind: RunKind, project: RTLProject) {
        guard !busy else { return }
        busy = true
        let synth = kind == .synthesis
        status = synth ? "Synthesizing…" : "Simulating…"
        console = ""
        output = nil
        if !synth { waveform = nil }
        let runner = RTLEngine()
        engine = runner
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("RTL Bench/Runs/\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                DispatchQueue.main.async { self.output = root }
                let sources = try project.writeSources(to: root.appendingPathComponent("sources"))
                let artifact = try runner.run(kind, design: sources.design, benches: sources.benches,
                    designTop: project.designTop, simulationTop: project.simulationTop,
                    output: root.appendingPathComponent("results"), durationNS: project.duration) { chunk in
                    DispatchQueue.main.async {
                        self.console += chunk
                        if self.console.utf8.count > 100_000 { self.console = String(self.console.suffix(70_000)) }
                    }
                }
                DispatchQueue.main.async {
                    self.output = artifact
                    if !synth { self.waveform = artifact }
                    self.finish(synth ? "Synthesis complete" : "Simulation complete")
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.console += "\n" + message + "\n"
                    self.finish(self.status == "Stopping…" ? "Run stopped" : (synth ? "Synthesis failed" : "Simulation failed"))
                }
            }
        }
    }
    private func finish(_ status: String) {
        busy = false
        engine = nil
        self.status = status
    }
}
