# StrayLite

Minimal SwiftPM iOS app that records synchronized RGB + LiDAR depth + camera
poses **and** a parametric room model (RoomPlan), producing a dataset
consumable by the [LightSet](https://github.com/Shadowru/LightSet) backend.

Designed for one specific environment: building entirely on Linux through
[xtool](https://github.com/xtool-org/xtool) without macOS or Xcode.
Implements the plan in `LightSet/new_version/handoff/07b-spm-refactor-for-xtool.md`.

## Status

| Step (per 07b plan) | Status |
|---------------------|--------|
| 1. Project skeleton | ✅ |
| 2. Capture pipeline (ARSession + preview) | ✅ |
| 3. RoomPlan integration | ✅ |
| 4. SwiftUI UI (list, detail, capture) | ✅ |
| 5. Persistence (JSON file — SwiftData macros don't expand on Linux) | ✅ |
| 6. Share/export (Files share sheet) | ✅ folder share; zip TODO |
| 7. Sign + install on device | ⏳ requires Apple Dev account + iPhone |
| 8. E2E test | ⏳ device-dependent |

`xtool dev` produces a working `straylite-App` arm64 Mach-O binary linked
to all needed system frameworks.

## Build recipe (verified on Ubuntu 22.04)

```bash
# 1. Swift 6.1.3 (NOT 6.2 or 6.3 — see "Compatibility quirks" below)
wget https://download.swift.org/swift-6.1.3-release/ubuntu2204/swift-6.1.3-RELEASE/swift-6.1.3-RELEASE-ubuntu22.04.tar.gz
mkdir -p ~/swift && tar -xzf swift-6.1.3-RELEASE-ubuntu22.04.tar.gz -C ~/swift --strip-components=1
export PATH=~/swift/usr/bin:$PATH

# 2. xtool AppImage
wget https://github.com/xtool-org/xtool/releases/download/1.16.1/xtool-x86_64.AppImage
chmod +x xtool-x86_64.AppImage

# 3. Darwin SDK from Xcode 16.3.xip
./xtool-x86_64.AppImage sdk install Xcode_16.3.xip  # ~30 min first time

# 4. Manually add a stub for CoreAudioTypes (header-only framework, missing .tbd)
SDK=~/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
cat > "$SDK/System/Library/Frameworks/CoreAudioTypes.framework/CoreAudioTypes.tbd" << 'EOF'
--- !tapi-tbd
tbd-version:     4
targets:         [ arm64-ios, arm64e-ios ]
install-name:    '/System/Library/Frameworks/CoreAudioTypes.framework/CoreAudioTypes'
current-version: 1.0.0
compatibility-version: 1.0.0
exports:
  - targets:    [ arm64-ios, arm64e-ios ]
    symbols:    [ ]
...
EOF

# 5. Build
git clone https://github.com/Shadowru/straylite.git
cd straylite
~/xtool-test/xtool-x86_64.AppImage dev   # build + sign + install if `xtool auth` done
```

## Compatibility quirks (learned the hard way)

1. **Use Swift 6.1.3, not 6.2 or 6.3.**
   - Swift 6.3.x ships a too-new clang whose `arm_neon.h` intrinsic
     signatures don't match the iOS 18.4 SDK headers, producing thousands
     of `incompatible constant for this __builtin_neon function` errors.
   - Swift 6.2.x compiler emits calls to `swift_coroFrameAlloc`, a
     runtime symbol that doesn't exist in the iOS 18.4 Swift runtime
     (iOS 18.4 ships Swift 6.1's runtime).
   - **Swift 6.1.3** matches Xcode 16.3's runtime ABI exactly.

2. **`CoreAudioTypes.framework` is header-only** on iOS — it has no `.tbd`
   stub. Many frameworks (RealityKit, SceneKit, even some ARKit paths)
   autolink it, so the linker fails. Workaround: write an empty stub
   `.tbd` into the SDK (see step 4 above).

3. **Avoid `RealityKit.ARView` and `SceneKit.ARSCNView`** for the camera
   preview. Both autolink CoreAudioTypes via their audio components.
   We instead grab `ARFrame.capturedImage` from the ARSessionDelegate
   and display it as a `CIImage`-backed `UIImage` (see
   `Capture/ARViewContainer.swift`).

4. **`@Preview` SwiftUI macros** don't expand on Linux toolchain — they
   require `PreviewsMacros` which is Xcode-bundled. Just delete `#Preview`
   blocks; they're dev-time only.

5. **SwiftData `@Model` and `@Query` macros** don't fully expand under
   xtool/Linux. Fallback to `Codable` structs + a tiny JSON-file
   `ObservableObject` store (see `Storage/SessionsStore.swift`).

## Architecture

```
Sources/straylite/
├── strayliteApp.swift             @main + WindowGroup + SessionsStore
├── ContentView.swift              NavigationStack root
├── Capture/
│   ├── CaptureView.swift          live screen with record button + timer
│   ├── ARViewContainer.swift      lightweight CIImage-based preview
│   └── CaptureCoordinator.swift   ARSession + RoomCaptureSession owner
├── Encoders/
│   ├── DatasetDirectory.swift     Documents/scans/<UUID>/
│   ├── RGBJPEGEncoder.swift       frame N → rgb/000NNN.jpg
│   ├── DepthEncoder.swift         depth float32 → 16-bit .bin (mm) + W,H sidecar
│   ├── OdometryCSVEncoder.swift   frame, timestamp, fx/fy/cx/cy, x/y/z, quaternion
│   └── RoomPlanExporter.swift     CapturedRoom → roomplan.{usdz,json}
├── Storage/
│   ├── Session.swift              Codable scan metadata
│   └── SessionsStore.swift        @MainActor ObservableObject over sessions.json
└── UI/
    ├── SessionListView.swift      list of scans, swipe-to-delete
    └── SessionDetailView.swift    metadata + share-folder button (UIActivityViewController)
```

## On-device output

Each scan produces in `Documents/scans/<UUID>/`:

```
rgb/000000.jpg, 000001.jpg, ...    every 5th frame, JPEG quality 88
depth/000000.bin                    UInt16 little-endian millimeters
depth/000000.bin.size               "W,H\n" sidecar
confidence/000000.bin               UInt8 ARConfidenceLevel.rawValue
odometry.csv                        per-frame pose + intrinsics (Stray-compat schema)
roomplan.usdz                       parametric room geometry (RoomPlan)
roomplan.json                       same as Codable JSON for non-USD backends
```

Plus `Documents/sessions.json` tracking session metadata across the app.

## Not done

- Zip export. Currently the share sheet exposes the folder; a `.zip`
  produced via `NSFileCoordinator` or `Compression` would upload faster.
- Manifest.json sidecar with app version, device model, scan-start
  position, etc.
- Settings screen (FPS divider, upload endpoint).
- HTTP upload to a configured backend (currently relies on AirDrop /
  Files share).
