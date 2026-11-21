# Vivado RTL workflow

## Synthesis

The design top identifies the circuit to build. AMD’s `bft` example reads VHDL and Verilog design files, loads constraints, synthesizes `bft` for a named FPGA and writes a checkpoint. Packages and other declarations must precede files that depend on them. Vivado supports synthesizable constructs in Verilog, SystemVerilog and VHDL. [AMD synthesis example](https://docs.amd.com/r/en-US/ug904-vivado-implementation/synth_design) · [Compilation order](https://docs.amd.com/r/2023.2-English/ug901-vivado-synthesis/Controlling-File-Compilation-Order) · [Supported design languages](https://docs.amd.com/api/khub/documents/agG3S93Yqy28Z4C9nY5zag/content)

## Behavioral simulation

The testbench top supplies stimulus and instantiates the design. Vivado includes design sources in the simulation set by default, so edits to the circuit carry into the next simulation. A behavioral run can start before synthesis. [AMD simulation settings](https://docs.amd.com/r/2024.1-English/ug900-vivado-logic-simulation/Using-Simulation-Settings) · [Behavioral simulation tutorial](https://docs.amd.com/r/2026.1-English/ug937-vivado-design-suite-simulation-tutorial/Step-3-Running-Behavioral-Simulation)

The Xilinx Tcl Store’s `xsim/sim.tcl` exposes the handoff. Its `compile` procedure writes and launches a compilation script. That script invokes `xvlog` for Verilog/SystemVerilog and `xvhdl` for VHDL as needed. `elaborate` produces and launches the next script, and `simulate` prepares the simulator command and waveform configuration. AMD’s tutorial identifies `xelab` as the snapshot builder and `xsim` as the engine that runs it. [Xilinx simulation adapter](https://github.com/Xilinx/XilinxTclStore/blob/4011ae63204a1bbbdfc2a92618e0c3ac9e4ee905/tclapp/xilinx/xsim/sim.tcl#L52-L100) · [AMD simulator stages](https://docs.amd.com/r/2026.1-English/ug937-vivado-design-suite-simulation-tutorial/Step-3-Running-Behavioral-Simulation)

## Reproducible adapter inspection

REA 6.10.1 inventoried the official Xilinx Tcl Store ZIP at commit `4011ae63204a1bbbdfc2a92618e0c3ac9e4ee905` and extracted the 177,184-byte `tclapp/xilinx/xsim/sim.tcl` member. The archive SHA-256 is `97f51d27cf8ec6336b8c22fb25c903265495d6cb9061e7042b753a19455d230f`. The extracted script SHA-256 is `fcefb1939c032bbe978f41ea6a12ab583303babc9eefcd246c572eff598b07fe`. [Pinned source archive](https://codeload.github.com/Xilinx/XilinxTclStore/zip/4011ae63204a1bbbdfc2a92618e0c3ac9e4ee905)

| REA operation | Evidence ID |
| --- | --- |
| Inspect archive | `ev_57753b013af6ff8165d951ae980cdd08673308cf511337f69ddc19d646d88612` |
| Extract selected adapter | `ev_e173b13293c64be63b3bbf1c07d589b017e18c3f6a98fa751a190473f95b360c` |

Reading the extracted Tcl identified the emitted Unix commands for Verilog and VHDL compilation, elaboration and snapshot simulation. The waveform configuration and simulation command file are prepared together. These are static observations of the adapter. [Verilog compiler](https://github.com/Xilinx/XilinxTclStore/blob/4011ae63204a1bbbdfc2a92618e0c3ac9e4ee905/tclapp/xilinx/xsim/sim.tcl#L3717-L3728) · [VHDL compiler](https://github.com/Xilinx/XilinxTclStore/blob/4011ae63204a1bbbdfc2a92618e0c3ac9e4ee905/tclapp/xilinx/xsim/sim.tcl#L3836-L3849) · [Elaboration](https://github.com/Xilinx/XilinxTclStore/blob/4011ae63204a1bbbdfc2a92618e0c3ac9e4ee905/tclapp/xilinx/xsim/sim.tcl#L1518-L1519) · [Simulation](https://github.com/Xilinx/XilinxTclStore/blob/4011ae63204a1bbbdfc2a92618e0c3ac9e4ee905/tclapp/xilinx/xsim/sim.tcl#L1849)

## Reconstruction scope

These observations establish two independent actions for the Mac app. Synthesis starts at the design top and produces a netlist. Simulation starts at the testbench top and exposes the resulting signal changes. The evidence comes from static inspection of the public Xilinx adapter and AMD’s manuals. A search of Applications, Downloads, Documents and standard tool locations on this Mac found no accessible Vivado executable or project. Vivado binary internals, runtime behavior on a particular installation and device-level equivalence remain unverified.
