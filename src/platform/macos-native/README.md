# Native macOS frontend

This directory contains the SwiftUI and Metal frontend for mGBA on Apple Silicon.
It links to the existing mGBA emulation core through the small C API in
`Sources/MGBABridge`.

From the repository root, build and launch it with:

```sh
./script/build_and_run.sh
```

The generated app is `dist/mGBA.app` and contains an arm64 executable.

## Native app features

- SwiftUI windows, menus, a floating activity-driven toolbar, and a dedicated Settings scene
- Metal-only video output with continuous aspect-fit scaling and filtering preferences
- Native ROM picker, Finder opening, and drag and drop
- Persistent recent games on the welcome screen and in the File menu
- Keyboard and GameController framework input
- Hold-Space 4× fast-forward with automatic audio suppression
- Stereo audio through AVAudioEngine
- Nine save-state slots, with quick save/load on Command-S and Command-L
- Battery saves and states stored in the app's Application Support directory

Run the native core integration test with:

```sh
swift test --package-path src/platform/macos-native
```

## Release packaging

Create an optimized, hardened-runtime arm64 app signed with the first installed
Developer ID Application identity:

```sh
./script/package_release.sh
```

The signed app and ZIP are written to `dist/release`. Override the automatically
selected certificate with `MGBA_SIGN_IDENTITY` when a Mac has multiple Developer
ID identities.

Notarization intentionally uses a Keychain profile instead of keeping Apple
credentials in this repository. After creating a `notarytool` profile, run:

```sh
MGBA_NOTARY_PROFILE=<profile-name> ./script/notarize_release.sh
```

That script submits the ZIP, waits for Apple, staples and validates the ticket,
recreates the ZIP, and performs a final Gatekeeper assessment.

## Metal shaders

Open **mGBA > Settings > Shaders** and choose a built-in Metal look:

- Native Pixels
- GBA Color
- LCD Grid
- Soft LCD
- Classic Green

Looks switch live and persist between launches. For a custom look, choose
**Import Metal Shader** and select a `.metal` source file. The file is copied
into the app's managed shader library and selected immediately. Imported shaders
can be revealed in Finder or moved to Trash from the same settings pane.

Custom shaders must export a fragment function named `mgba_fragment`. Its input
layout and texture binding are:

```metal
#include <metal_stdlib>
using namespace metal;

struct MGBARasterData {
    float4 position [[position]];
    float2 textureCoordinate;
};

fragment float4 mgba_fragment(
    MGBARasterData input [[stage_in]],
    texture2d<float> frame [[texture(0)]]) {
    constexpr sampler source(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 color = frame.sample(source, input.textureCoordinate);
    return float4(color.rgb, 1.0);
}
```
