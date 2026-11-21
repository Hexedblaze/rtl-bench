# RTL Bench

RTL Bench is a native Mac editor, synthesizer front end and behavioral simulator for Apple silicon on macOS 26 or later. The app bundles Yosys, Icarus Verilog and GHDL. VHDL simulation also uses the linker from Apple’s Command Line Tools or Xcode.

## Install

Download **RTL-Bench.dmg** from [GitHub Releases](https://github.com/Hexedblaze/rtl-bench/releases/latest). Open the disk image and drag **RTL Bench** into **Applications**. This build is ad-hoc signed.

## Try the counter

Open **RTL Bench.app** and choose **Examples → SystemVerilog Counter**. Press **⌘R** to run its self-checking testbench. In **Waveform**, click a trace or use the time slider to inspect the count at each clock edge. After reset, five rising edges take the count to 5. **Run log** shows the testbench’s PASS message. Press **⌘B** to synthesize the counter. **Show output** reveals the generated Verilog netlist in Finder.

The Examples menu also offers Verilog and VHDL versions. File → Save stores the editor contents, file order, top names and simulation duration together in a portable `.rtlbench` project.

## Use an existing design

Use **+** beside **Sources** to import design files and testbench files. Import copies UTF-8 source text into the project. Right-click a source to rename it, change its role or move it earlier in compilation order. Include Verilog headers as design sources. Source names share one directory. Put VHDL packages before their users. Set **Design top** to the module/entity to synthesize and **Simulation top** to the testbench module/entity. Simulation runs until the requested duration, an explicit finish, or a failure. **Stop** interrupts a running tool.

The synthesizer emits a generic logical netlist. Device placement, routing, timing closure, encrypted IP, FPGA programming and Vivado project import are outside this build. A run accepts Verilog/SystemVerilog together or VHDL separately in the `work` library. SystemVerilog coverage follows the Yosys and Icarus front ends. Use VHDL-2008 for VHDL sources. Project snapshots include HDL files and headers. Testbenches that read external data need an accessible path to those files.

Each run retains a source snapshot, tool logs and generated output under `~/Library/Application Support/RTL Bench/Runs/`. Synthesis writes `netlist.v`. Simulation writes `waves.vcd`. The waveform preview displays the first 2 MB, 256 signal declarations and 100,000 value changes, stopping at the first limit. **Reveal VCD** locates the complete trace.

## Build and verify

To build a complete app from a fresh checkout, install Apple’s Command Line Tools or Xcode with the macOS 26 SDK. From the repository root, download the pinned Apple silicon toolchain, check its digest and build the app.

```sh
(
  set -e
  tools_dir=$(mktemp -d)
  archive=oss-cad-suite-darwin-arm64-20261120.tgz
  cd "$tools_dir"
  curl -fLO "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-11-20/$archive"
  echo "7726101208c3d8ac7482dacd409f91bf6d5aed573905020e90e7ec4d064ef970  $archive" | shasum -a 256 -c -
  tar -xzf "$archive"
  cd -
  ./build.sh "./RTL Bench.app" "$tools_dir/oss-cad-suite"
  "./RTL Bench.app/Contents/MacOS/RTLBench" --self-check "$TMPDIR"
)
```

The check round-trips all three example projects, synthesizes each, runs its testbench against the source and the generated netlist, and checks the VCD data for the final count. It prints the path to its saved results.

The packaging script records the upstream archive URL, exact SHA-256 and copied components. The bundled suite contains its component manifest and upstream notices. [OSS CAD Suite release](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-11-20)
