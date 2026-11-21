import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let rtlBench = UTType(exportedAs: "local.rtlbench.project", conformingTo: .json)
}

enum SourceRole: String, Codable, CaseIterable {
    case design = "Design"
    case bench = "Testbench"
}

struct HDLFile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var role: SourceRole
    var text: String
}

enum BenchError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct RTLProject: FileDocument, Codable, Equatable {
    static let readableContentTypes = [UTType.rtlBench]
    var version = 1
    var designTop = "counter"
    var simulationTop = "counter_tb"
    var duration = 100
    var files: [HDLFile]

    init(files: [HDLFile]) { self.files = files }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BenchError.message("This project must be a regular .rtlbench file.")
        }
        self = try JSONDecoder().decode(Self.self, from: data)
        try validate()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(self))
    }

    static func validateName(_ name: String) throws {
        let suffix = (name as NSString).pathExtension.lowercased()
        guard !name.isEmpty, !name.hasPrefix("."), !name.hasPrefix("-"),
              !name.contains("/"), !name.contains(":"), !name.contains("\\"),
              name.rangeOfCharacter(from: .controlCharacters) == nil,
              ["v", "sv", "vh", "svh", "vhd", "vhdl"].contains(suffix) else {
            throw BenchError.message("Use a file name such as counter.sv, defs.vh, or decoder.vhd. Subfolders are unsupported.")
        }
    }

    func validate() throws {
        guard version == 1 else { throw BenchError.message("This project needs a newer version of RTL Bench.") }
        var names = Set<String>()
        var ids = Set<UUID>()
        for file in files {
            try Self.validateName(file.name)
            guard names.insert(file.name.precomposedStringWithCanonicalMapping.lowercased()).inserted, ids.insert(file.id).inserted else {
                throw BenchError.message("Each source needs a unique name and ID. Check \(file.name).")
            }
        }
    }

    func writeSources(to directory: URL) throws -> (design: [URL], benches: [URL]) {
        try validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var design: [URL] = [], benches: [URL] = []
        for file in files {
            let url = directory.appendingPathComponent(file.name)
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            if file.role == .design { design.append(url) } else { benches.append(url) }
        }
        return (design, benches)
    }

    static func counter(_ language: String = "SystemVerilog") -> RTLProject {
        let body: String, test: String, ext: String
        if language == "VHDL" {
            ext = "vhd"
            body = """
            library ieee;
            use ieee.std_logic_1164.all;
            use ieee.numeric_std.all;

            entity counter is
              port (clk, reset : in std_logic;
                    count : out unsigned(3 downto 0));
            end entity;

            architecture rtl of counter is
            begin
              process (clk)
              begin
                if rising_edge(clk) then
                  if reset = '1' then
                    count <= (others => '0');
                  else
                    count <= count + 1;
                  end if;
                end if;
              end process;
            end architecture;
            """
            test = """
            library ieee;
            use ieee.std_logic_1164.all;
            use ieee.numeric_std.all;

            entity counter_tb is end;
            architecture test of counter_tb is
              signal clk : std_logic := '0';
              signal reset : std_logic := '1';
              signal count : unsigned(3 downto 0);
            begin
              dut : entity work.counter port map (clk, reset, count);
              clk <= not clk after 5 ns;
              process
              begin
                wait for 6 ns;
                assert count = 0 report "reset failed" severity failure;
                reset <= '0';
                for i in 1 to 5 loop
                  wait until rising_edge(clk);
                  wait for 1 ns;
                  assert count = i report "count mismatch" severity failure;
                end loop;
                report "PASS: reset and five rising edges";
                std.env.finish;
                wait;
              end process;
            end architecture;
            """
        } else {
            let sv = language == "SystemVerilog"
            ext = sv ? "sv" : "v"
            body = """
            `timescale 1ns/1ps

            module counter (
                input  wire       clk,
                input  wire       reset,
                output \(sv ? "logic" : "reg") [3:0] count
            );
                \(sv ? "always_ff" : "always") @(posedge clk) begin
                    if (reset)
                        count <= 4'd0;
                    else
                        count <= count + 1'b1;
                end
            endmodule
            """
            test = """
            `timescale 1ns/1ps

            module counter_tb;
                reg clk = 0;
                reg reset = 1;
                wire [3:0] count;
                integer i;

                counter dut (.clk(clk), .reset(reset), .count(count));
                always #5 clk = ~clk;

                initial begin
                    #6;
                    if (count !== 0) $fatal(1, "reset failed");
                    reset = 0;
                    for (i = 1; i <= 5; i = i + 1) begin
                        @(posedge clk);
                        #1;
                        if (count !== i) $fatal(1, "count mismatch");
                    end
                    $display("PASS: reset and five rising edges");
                    $finish;
                end
            endmodule
            """
        }
        return RTLProject(files: [
            HDLFile(name: "counter.\(ext)", role: .design, text: body + "\n"),
            HDLFile(name: "counter_tb.\(ext)", role: .bench, text: test + "\n")
        ])
    }
}
