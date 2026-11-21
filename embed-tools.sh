#!/bin/bash
# Usage: embed-tools.sh <extracted oss-cad-suite> <RTL Bench.app>
# Download: https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-11-20/oss-cad-suite-darwin-arm64-20261120.tgz
# Archive SHA-256: 7726101208c3d8ac7482dacd409f91bf6d5aed573905020e90e7ec4d064ef970
set -eu
if [[ $# != 2 || ! -d "$1" || "$2" != *.app ]]; then
    echo 'Usage: embed-tools.sh <extracted oss-cad-suite> <RTL Bench.app>' >&2
    exit 2
fi
source_dir=$(cd "$1" && pwd)
if [[ $(cat "$source_dir/VERSION") != 20261120 ]] || ! /usr/bin/lipo -verify_arch arm64 "$source_dir/libexec/ghdl"; then
    echo 'Expected OSS CAD Suite darwin-arm64 20261120.' >&2
    exit 1
fi
runtime="$2/Contents/Resources/oss-cad-suite"
mkdir -p "$runtime"
runtime=$(cd "$runtime" && pwd)
cd "$source_dir"
copy() {
    for item in "$@"; do
        mkdir -p "$runtime/$(dirname "$item")"
        cp -Rp "$item" "$runtime/$(dirname "$item")/"
    done
}
copy VERSION share/manifest.json license/{LICENSE.ghdl,LICENSE.iverilog,LICENSE.yosys}
copy bin/{yosys,yosys-abc,iverilog,vvp,ghdl,ghdl1-llvm}
copy libexec/{realpath,yosys,yosys-abc,iverilog,vvp,ivl,ivlpp,ghdl,ghdl1-llvm}
copy lib/{yosys-abc,tcl8.6,ghdl} share/yosys/*.v
copy lib/ivl/{ivl,ivlpp,include,vvp.tgt,vvp.conf,vvp-s.conf} lib/ivl/*.vpi
copy lib/lib{ffi.8,z.1.3.2,tcl8.6,readline.8.3,ncurses.6,bz2.1.0.8,vvp.1.14.0,gcc_s.1.1}.dylib
# Icarus launches its helper programs through a shell without quoting their paths.
# A short, private alias also protects bundle names containing shell punctuation.
cat > "$runtime/bin/iverilog" <<'WRAPPER'
#!/bin/bash
set -eu
suite=$(cd "$(dirname "$0")/.." && pwd -P)
alias_dir=$(mktemp -d ./.rtlbench-ivl.XXXXXX)
trap 'rm -f "$alias_dir/ivl"; rmdir "$alias_dir"' EXIT
ln -s "$suite/lib/ivl" "$alias_dir/ivl"
"$suite/libexec/iverilog" -B "$alias_dir/ivl" -B "M$suite/lib/ivl" -p "VVP_EXECUTABLE=$suite/bin/vvp" "$@"
WRAPPER
