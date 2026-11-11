#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build >/dev/null
binary_dir="$(swift build --show-bin-path)"
benchmark_dir="$(mktemp -d -t privacy-render-benchmark)"
trap 'rm -rf "$benchmark_dir"' EXIT
swiftc -I "$binary_dir/Modules" Sources/PrivacyAirPods/BlurRenderer.swift Sources/PrivacyAirPods/MetalPresenter.swift scripts/benchmark-renderer.swift "$binary_dir"/PrivacyCore.build/*.o -o "$benchmark_dir/benchmark"
"$benchmark_dir/benchmark"
