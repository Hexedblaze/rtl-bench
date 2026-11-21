import SwiftUI
import Darwin

@main
enum Entry {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--self-check" {
            do {
                try selfCheck(in: URL(fileURLWithPath: args[2], isDirectory: true))
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        } else { RTLBenchApp.main() }
    }

    private static func selfCheck(in folder: URL) throws {
        let fm = FileManager.default
        let suite = folder.appendingPathComponent("RTL Bench checks " + UUID().uuidString)
        try fm.createDirectory(at: suite, withIntermediateDirectories: true)
        for language in ["Verilog", "SystemVerilog", "VHDL"] {
            let root = suite.appendingPathComponent(language)
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            let project = RTLProject.counter(language)
            let encoded = try JSONEncoder().encode(project)
            let decoded = try JSONDecoder().decode(RTLProject.self, from: encoded)
            guard decoded == project else { throw BenchError.message("Project round-trip failed.") }
            let sources = try decoded.writeSources(to: root.appendingPathComponent("Design files"))
            func run(_ kind: RunKind, _ design: [URL], _ benches: [URL], _ directory: String) throws -> URL {
                var diagnostic = ""
                let result: URL
                do {
                    result = try RTLEngine().run(kind, design: design, benches: benches, designTop: project.designTop,
                        simulationTop: project.simulationTop, output: root.appendingPathComponent(directory),
                        durationNS: project.duration) { diagnostic += $0 }
                } catch {
                    throw BenchError.message(language + "\n" + diagnostic + "\n" + error.localizedDescription)
                }
                if kind == .simulation {
                    guard diagnostic.contains("PASS: reset and five rising edges") else {
                        throw BenchError.message("Counter testbench did not finish.\n" + diagnostic)
                    }
                    let trace = try VCDTrace.load(result)
                    let hasExpectedCount = trace.signals.contains { signal in
                        signal.width == 4 && signal.name.contains("count") &&
                            Int(trace.value(for: signal, at: trace.end), radix: 2) == 5
                    }
                    guard hasExpectedCount else {
                        throw BenchError.message("Expected the waveform to finish with count = 5 in \(result.path).")
                    }
                }
                return result
            }
            let netlist = try run(.synthesis, sources.design, [], "synth")
            _ = try run(.simulation, sources.design, sources.benches, "rtl sim")
            let bench = root.appendingPathComponent("netlist_tb.v")
            try RTLProject.counter("Verilog").files[1].text.write(to: bench, atomically: true, encoding: .utf8)
            _ = try run(.simulation, [netlist], [bench], "netlist sim")
            print("PASS \(language): project round-trip, synthesis, RTL simulation, netlist simulation and VCD values")
        }
        print("Verification artifacts: \(suite.path)")
    }
}
