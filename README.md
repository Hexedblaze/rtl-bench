# RTL Bench

Write Verilog, SystemVerilog, or VHDL on your Mac. Run a testbench to see how signals change over time, or synthesize your design into a Verilog netlist.

**[Download RTL Bench for Mac (.dmg)](https://github.com/Hexedblaze/rtl-bench/releases/latest/download/RTL-Bench.dmg)**

Requires an Apple silicon Mac running macOS 26 or later. The HDL tools come bundled with the app. VHDL simulation also uses Apple’s Command Line Tools or Xcode.

## Install

1. Open **RTL-Bench.dmg** from your Downloads folder.
2. Drag **RTL Bench** onto the **Applications** folder in the installer window.
3. Open **RTL Bench** from Applications.

This release uses an ad hoc signature. If macOS displays a security alert, see [Apple’s guide to opening apps on your Mac](https://support.apple.com/en-us/102445).

## Run your first simulation

New projects open with a four-bit counter and its testbench. Press **⌘R** to simulate it. In **Waveform**, click the clock edges to see the counter advance from 0 to 5 after reset. Press **⌘B** to synthesize the same design, then **Show output** to find the netlist.

The **Examples** menu has counters in all three languages. To run your own design, use **+** beside **Sources** to add your design and testbench files. [Using your own HDL files](Using-RTL-Bench.md)
