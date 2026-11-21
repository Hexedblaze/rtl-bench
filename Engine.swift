import Foundation
import Darwin

enum RunKind { case synthesis, simulation }

private struct RunError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// One worker owns a run. The UI can call cancel() at any time.
final class RTLEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var active: Process?
    private let fm = FileManager.default

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process = active, process.isRunning {
            let pid = process.processIdentifier
            // Wrappers and ABC may spawn children in the tool's process group.
            kill(getpgid(pid) == pid ? -pid : pid, SIGKILL)
        }
    }

    func run(_ kind: RunKind, design: [URL], benches: [URL], designTop: String,
             simulationTop: String, output: URL, durationNS: Int = 1000,
             log: (String) -> Void) throws -> URL {
        let top = (kind == .synthesis ? designTop : simulationTop).trimmingCharacters(in: .whitespacesAndNewlines)
        guard top.range(of: #"\A[A-Za-z_][A-Za-z0-9_$]*\z"#, options: .regularExpression) != nil else {
            throw RunError("Enter a simple module or entity name for the selected top.")
        }
        guard kind == .synthesis || durationNS > 0 else { throw RunError("Simulation duration must be positive.") }
        let files = design + (kind == .simulation ? benches : [])
        let headers = ["vh", "svh"]
        let units = files.filter { !headers.contains($0.pathExtension.lowercased()) }
        guard !design.isEmpty && !units.isEmpty else { throw RunError("Add at least one design source.") }
        let vhdl = ["vhd", "vhdl"].contains(units[0].pathExtension.lowercased())
        let allowed = vhdl ? ["vhd", "vhdl"] : ["v", "sv"] + headers
        var includeDirs: [String] = []
        for url in files {
            guard allowed.contains(url.pathExtension.lowercased()) else {
                throw RunError("A run supports either VHDL or the Verilog/SystemVerilog family. Check \(url.lastPathComponent).")
            }
            guard fm.isReadableFile(atPath: url.path) else { throw RunError("Cannot read \(url.path).") }
            let dir = url.deletingLastPathComponent().path
            if !includeDirs.contains(dir) { includeDirs.append(dir) }
        }

        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        guard try fm.contentsOfDirectory(atPath: output.path).isEmpty else {
            throw RunError("Use a new output directory for each run.")
        }
        let result = output.appendingPathComponent(kind == .synthesis ? "netlist.v" : "waves.vcd")
        func tool(_ name: String, _ args: [String], stdout: URL? = nil) throws {
            try invoke(name, args, in: output, stdout: stdout, log: log)
        }
        var rtl = units.map(\.path)
        if vhdl {
            try tool("ghdl", ["-a", "--std=08"] + rtl)
            if kind == .simulation {
                try tool("ghdl", ["--elab-run", "--std=08", top, "--stop-time=\(durationNS)ns",
                                  "--assert-level=error", "--vcd=waves.vcd"])
            } else {
                let intermediate = output.appendingPathComponent("elaborated.v")
                try tool("ghdl", ["--synth", "--std=08", "--out=verilog", top], stdout: intermediate)
                rtl = [intermediate.path]
            }
        }
        if kind == .synthesis {
            let yosysTop = vhdl ? top.lowercased() : top
            let script = """
            yosys read_verilog {*}$argv
            yosys hierarchy -check -top {\(yosysTop)}
            yosys synth -top {\(yosysTop)}
            yosys check -assert
            yosys stat
            yosys write_verilog -noattr netlist.v
            """
            try script.write(to: output.appendingPathComponent("synth.tcl"), atomically: true, encoding: .utf8)
            // Tcl receives each path as a distinct argv element, including paths with spaces.
            let sv = files.contains { ["sv", "svh"].contains($0.pathExtension.lowercased()) }
            let readerArgs = (sv ? ["-sv"] : []) + includeDirs.map { "-I" + $0 } + rtl
            try tool("yosys", ["-Q", "-T", "-c", "synth.tcl", "--"] + readerArgs)
        } else if !vhdl {
            let monitor = "rtlbench_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let trace = """
            `timescale 1ns/1ps
            module \(monitor);
              initial begin
                $dumpfile("waves.vcd");
                $dumpvars(0, \(top));
              end
              initial #(\(durationNS)) $finish;
            endmodule
            """
            try trace.write(to: output.appendingPathComponent("trace.v"), atomically: true, encoding: .utf8)
            // xelab defaults to 1 ns / 1 ps for modules without a time unit.
            try "+timescale+1ns/1ps\n".write(to: output.appendingPathComponent("simulation.f"), atomically: true, encoding: .utf8)
            let flags = ["-g2012", "-grelative-include", "-f", "simulation.f", "-s", monitor, "-s", top, "-o", "simulation.vvp"]
            try tool("iverilog", flags + includeDirs.map { "-I" + $0 } + rtl + ["trace.v"])
            try tool("vvp", ["-N", "simulation.vvp", "-vcd"])
            // A testbench may select its own $dumpfile before our monitor runs.
            if !fm.fileExists(atPath: result.path) {
                let alternatives = try fm.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension.lowercased() == "vcd" }
                if alternatives.count == 1 { try fm.copyItem(at: alternatives[0], to: result) }
            }
        }
        guard let size = try? result.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw RunError("The tool finished without producing \(result.lastPathComponent). Check the run log and testbench.")
        }
        return result
    }

    private func executable(_ name: String) throws -> URL {
        let env = ProcessInfo.processInfo.environment
        var dirs: [String] = []
        if let suite = env["RTL_BENCH_TOOLCHAIN"], !suite.isEmpty {
            dirs += [suite + "/bin", suite]
        }
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("oss-cad-suite/bin").path)
        }
        dirs.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("oss-cad-suite/bin").path)
        dirs += (env["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += ["/opt/homebrew/bin", "/usr/local/bin"]
        for dir in dirs where dir.hasPrefix("/") {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        throw RunError("Cannot find \(name). Place oss-cad-suite beside RTL Bench.app, or install \(name) in your Homebrew bin directory.")
    }

    private func invoke(_ name: String, _ args: [String], in dir: URL, stdout: URL?, log: (String) -> Void) throws {
        let process = Process()
        let executable = try executable(name)
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = executable.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        // A file avoids pipe deadlocks even when compilers emit megabytes of diagnostics.
        let diagnosticURL = dir.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).log")
        try Data().write(to: diagnosticURL, options: .withoutOverwriting)
        let diagnostic = try FileHandle(forWritingTo: diagnosticURL)
        defer { try? diagnostic.close() }
        var generated: FileHandle?
        if let stdout {
            try Data().write(to: stdout, options: .withoutOverwriting)
            generated = try FileHandle(forWritingTo: stdout)
        }
        defer { try? generated?.close() }
        process.standardOutput = generated ?? diagnostic
        process.standardError = diagnostic
        log("› " + ([name] + args).joined(separator: " ") + "\n")
        try lock.withLock {
            guard !cancelled else { throw RunError("Run stopped.") }
            try process.run()
            active = process
        }
        process.waitUntilExit()
        let stopped = lock.withLock {
            active = nil
            return cancelled
        }
        let reader = try FileHandle(forReadingFrom: diagnosticURL)
        defer { try? reader.close() }
        let count = try reader.seekToEnd()
        let preview: UInt64 = 48 * 1024
        if count > preview { log("Full diagnostics in \(diagnosticURL.lastPathComponent). Showing the last 48 KB.\n") }
        try reader.seek(toOffset: count > preview ? count - preview : 0)
        if let data = try reader.read(upToCount: Int(preview)), !data.isEmpty {
            log(String(decoding: data, as: UTF8.self) + "\n")
        }
        if stopped { throw RunError("Run stopped.") }
        guard process.terminationStatus == 0 else {
            throw RunError("\(name) exited with status \(process.terminationStatus). See the run log.")
        }
    }
}
