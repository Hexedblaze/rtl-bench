import SwiftUI
import AppKit

struct RTLBenchApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: RTLProject.counter()) { file in
            BenchWindow(project: file.$document)
                .frame(minWidth: 920, minHeight: 640)
        }
        .defaultSize(width: 1150, height: 790)
        .commands { ExampleCommands() }
    }
}

private struct ExampleCommands: Commands {
    @Environment(\.newDocument) private var newDocument
    var body: some Commands {
        CommandMenu("Examples") {
            ForEach(["Verilog", "SystemVerilog", "VHDL"], id: \.self) { language in
                Button("\(language) Counter") { newDocument(RTLProject.counter(language)) }
            }
        }
    }
}

struct BenchWindow: View {
    @Binding var project: RTLProject
    @State private var selected: UUID?
    @State private var resultTab = "Log"
    @State private var sheet: SourceForm?
    @State private var problem: String?
    @State private var removing: UUID?
    @StateObject private var runs = Runs()

    private var selectedFile: HDLFile? {
        project.files.first { $0.id == selected } ?? project.files.first
    }
    private func language(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "vhd", "vhdl": return "VHDL"
        case "sv", "svh": return "SystemVerilog"
        default: return "Verilog"
        }
    }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 205, idealWidth: 230, maxWidth: 315)
            VSplitView {
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(.teal)
                        Text(selectedFile?.name ?? "Source editor").font(.headline)
                        Spacer()
                        if let file = selectedFile { Text(language(file.name)).foregroundStyle(.secondary).font(.caption) }
                    }.padding(.horizontal, 16).frame(height: 42)
                    Divider()
                    if let file = selectedFile {
                        CodeEditor(source: Binding(get: {
                            project.files.first { $0.id == file.id }?.text ?? ""
                        }, set: { value in
                            if let index = project.files.firstIndex(where: { $0.id == file.id }) { project.files[index].text = value }
                        }), isVHDL: language(file.name) == "VHDL")
                        .id(file.id)
                    } else {
                        VStack(spacing: 10) {
                            Text("Add a design source to start editing.").foregroundStyle(.secondary)
                            Button("New Source…") { sheet = SourceForm() }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(minHeight: 215)
                results.frame(minHeight: 175, idealHeight: 245)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if runs.busy { Button { runs.stop() } label: { Label("Stop", systemImage: "stop.fill") } }
                Button { start(.synthesis) } label: { Label("Synthesize", systemImage: "cpu") }
                    .keyboardShortcut("b", modifiers: .command).disabled(runs.busy)
                    .help("Synthesize the design top (⌘B)")
                Button { start(.simulation) } label: { Label("Simulate", systemImage: "play.fill") }
                    .keyboardShortcut("r", modifiers: .command).disabled(runs.busy)
                    .help("Simulate the testbench (⌘R)")
            }
        }
        .sheet(item: $sheet) { form in
            SourceSheet(initial: form, commit: { name, role in
                try RTLProject.validateName(name)
                guard !project.files.contains(where: { $0.id != form.editing && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw BenchError.message("The project already contains \(name).")
                }
                if let editing = form.editing, let i = project.files.firstIndex(where: { $0.id == editing }) {
                    project.files[i].name = name
                    project.files[i].role = role
                } else {
                    let source = HDLFile(name: name, role: role, text: "")
                    project.files.append(source)
                    selected = source.id
                }
                sheet = nil
            }, cancel: { sheet = nil })
        }
        .alert("Project error", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
        .confirmationDialog("Remove source from this project?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove Source", role: .destructive) {
                if let removing { project.files.removeAll { $0.id == removing } }
                self.removing = nil
            }
        }
        .onChange(of: runs.waveform) { if runs.waveform != nil { resultTab = "Wave" } }
        .onDisappear { if runs.busy { runs.stop() } }
    }

    private func start(_ kind: RunKind) {
        resultTab = "Log"
        runs.start(kind, project: project)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sources").font(.title3.bold())
                Spacer()
                Menu {
                    Button("New Source…") { sheet = SourceForm() }
                    Button("Import Design Files…") { importFiles(.design) }
                    Button("Import Testbench Files…") { importFiles(.bench) }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).fixedSize().help("Add sources")
            }.padding([.leading, .trailing, .top], 15).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SourceRole.allCases, id: \.self) { role in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(role == .design ? "Design sources" : "Simulation sources")
                                .font(.caption.bold()).foregroundStyle(.secondary).padding(.leading, 7)
                            ForEach(project.files.filter { $0.role == role }) { file in
                                Button { selected = file.id } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: role == .design ? "doc.text" : "waveform.path.ecg").foregroundStyle(.teal)
                                        Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Spacer()
                                    }.padding(7).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                .background(selectedFile?.id == file.id ? Color.teal.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contextMenu {
                                    Button("Rename or Change Role…") { sheet = SourceForm(editing: file.id, name: file.name, role: file.role) }
                                    Button("Move Earlier") { move(file, -1) }.disabled(neighbor(file, -1) == nil)
                                    Button("Move Later") { move(file, 1) }.disabled(neighbor(file, 1) == nil)
                                    Divider()
                                    Button("Remove…", role: .destructive) { removing = file.id }
                                }
                            }
                            if !project.files.contains(where: { $0.role == role }) {
                                Button("Add files…") { importFiles(role) }.buttonStyle(.link).padding(.leading, 7)
                            }
                        }
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Run settings").font(.headline).padding(.bottom, 4)
                Text("Design top").font(.caption).foregroundStyle(.secondary)
                TextField("Module or entity", text: $project.designTop)
                Text("Simulation top").font(.caption).foregroundStyle(.secondary)
                TextField("Testbench module or entity", text: $project.simulationTop)
                Text("Simulation duration (ns)").font(.caption).foregroundStyle(.secondary)
                TextField("Nanoseconds", value: $project.duration, format: .number.grouping(.never))
            }.textFieldStyle(.roundedBorder).padding(15)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Results", selection: $resultTab) {
                    Text("Run log").tag("Log")
                    Text("Waveform").tag("Wave")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
                if runs.busy { ProgressView().controlSize(.small) }
                Text(runs.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let output = runs.output {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([output]) } label: {
                        Label("Show output", systemImage: "folder")
                    }.controlSize(.small)
                }
            }.padding(.horizontal, 12).frame(height: 43)
            Divider()
            if resultTab == "Wave" {
                if let url = runs.waveform { WaveformView(url: url).id(url) }
                else { placeholder("waveform.path.ecg", "Run a simulation to inspect signals.") }
            } else if runs.console.isEmpty {
                placeholder("terminal", runs.busy ? "Starting toolchain…" : "Synthesize the design or simulate the testbench.")
            } else {
                ScrollViewReader { reader in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(runs.console).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Color.clear.frame(height: 1).id("end")
                        }.padding(10)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: runs.console) { reader.scrollTo("end", anchor: .bottomLeading) }
                }
            }
        }
    }
    private func placeholder(_ icon: String, _ message: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.title3)
            Text(message).font(.callout)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func neighbor(_ file: HDLFile, _ direction: Int) -> HDLFile? {
        let siblings = project.files.filter { $0.role == file.role }
        guard let index = siblings.firstIndex(where: { $0.id == file.id }), siblings.indices.contains(index + direction) else { return nil }
        return siblings[index + direction]
    }
    private func move(_ file: HDLFile, _ direction: Int) {
        guard let other = neighbor(file, direction), let i = project.files.firstIndex(of: file), let j = project.files.firstIndex(of: other) else { return }
        project.files.swapAt(i, j)
    }
    private func importFiles(_ role: SourceRole) {
        let panel = NSOpenPanel()
        panel.title = role == .design ? "Import design sources" : "Import simulation sources"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["sv", "v", "svh", "vh", "vhd", "vhdl"].compactMap { .init(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        do {
            var updated = project
            for url in panel.urls {
                let text = try String(contentsOf: url, encoding: .utf8)
                updated.files.append(HDLFile(name: url.lastPathComponent, role: role, text: text))
            }
            try updated.validate()
            project = updated
            selected = updated.files.last?.id
        } catch { problem = error.localizedDescription }
    }
}

struct SourceForm: Identifiable {
    let id = UUID()
    var editing: UUID?
    var name = "module.sv"
    var role: SourceRole = .design
}
struct SourceSheet: View {
    @State private var name: String
    @State private var role: SourceRole
    @State private var error = ""
    let initial: SourceForm
    let commit: (String, SourceRole) throws -> Void
    let cancel: () -> Void

    init(initial: SourceForm, commit: @escaping (String, SourceRole) throws -> Void, cancel: @escaping () -> Void) {
        self.initial = initial
        _name = State(initialValue: initial.name)
        _role = State(initialValue: initial.role)
        self.commit = commit
        self.cancel = cancel
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(initial.editing == nil ? "New source" : "Source settings").font(.title3.bold())
            TextField("File name", text: $name).textFieldStyle(.roundedBorder)
            Picker("Use as", selection: $role) { ForEach(SourceRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { do { try commit(name, role) } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 350)
    }
}
