#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -parse-as-library \
    BoringNotchXPCHelper/PeripheralBatteryService.swift \
    BoringNotchXPCHelper/MicrophoneService.swift \
    scripts/tests/DeviceControlsChecks.swift -o "$check_dir/checks"
"$check_dir/checks"
xcrun swiftc -parse-as-library \
    BoringNotchXPCHelper/MicrophoneService.swift \
    scripts/tests/MicrophoneMutationChecks.swift -o "$check_dir/microphone-checks"
"$check_dir/microphone-checks"
