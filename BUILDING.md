# Building RTL Bench from source

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
