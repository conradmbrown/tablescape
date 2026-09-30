# Native visionOS client

A Swift client for the shared revision-274 gateway. **Metal/MetalKit** renders the main preview and minimap; **Metal through Compositor Services** renders the immersive stereo board, with **ARKit** placement/tracking. The independent table window uses **RealityKit** geometry and system window controls. **SwiftUI** provides the persistent toolbelt and gameplay panels. Unity is not required to build this client.

## Prerequisites and storage

- Apple silicon Mac, full Xcode 26 with visionOS 26 SDK and a compatible Simulator device/runtime.
- Python 3.10+, XcodeGen, Git, ripgrep, SSH, rsync and curl. For existing Homebrew installations: `brew install xcodegen ripgrep`.
- A mounted development disk with at least 8 GB free; allow more for retained build/test results.
- A separately provisioned revision-274 game gateway for connected play. Offline builds and model checks do not need a server.

Select the full Xcode developer directory in Xcode's Locations settings. Check `xcodebuild -version`, `xcrun --sdk xrsimulator --show-sdk-version`, `xcrun simctl list devices available`, `python3 --version` and `xcodegen --version`. Install a visionOS runtime/device through Xcode if needed. The app compiles its packaged Metal shader source at runtime; these scripts do not download an optional Metal toolchain.

Configure your own existing disk and workspace in the shell:

```sh
export SCAPE_STORAGE_ROOT='/path/to/mounted-development-disk'
export SCAPE_WORKSPACE="$SCAPE_STORAGE_ROOT/TableScape"
```

Replace the placeholder before running commands. Do not create a mount directory to stand in for a missing disk. Build/test launchers validate the mounted disk, resolved checkout, workspace and output paths through `scripts/storage-env.sh`; symlinks cannot redirect output outside that disk. `SCAPE_BUILD_ROOT` optionally overrides the default `$SCAPE_WORKSPACE/Build`, but must stay inside the configured disk. Shell configuration belongs outside Git.

Apple-managed simulator data, installed tools, signing configuration and some system caches still occupy the internal disk. The storage guard does not promise zero system-disk growth.

## Clone and prepare assets

```sh
python3 -c 'import os; p=os.environ["SCAPE_STORAGE_ROOT"]; assert os.path.ismount(p) and p != "/", "Choose an existing development-disk mount"'
mkdir -p "$SCAPE_WORKSPACE"
git clone --branch main \
  https://github.com/innoiso/tablescape.git "$SCAPE_WORKSPACE/Source"
cd "$SCAPE_WORKSPACE/Source"
python3 scripts/import-game-assets.py --from-unity-assets \
  '/path/to/existing/TableScape/Unity/Assets'
python3 scripts/native-assets.py build --source "$PWD" \
  --output "$SCAPE_WORKSPACE/Assets/revision274-v1"
rsync -a "$SCAPE_WORKSPACE/Assets/revision274-v1/" Native/TableScape/Resources/
python3 scripts/native-assets.py verify --output Native/TableScape/Resources
```

For an existing checkout, inspect `git status` and update it without replacing local changes. Native resources are generated from separately supplied, ignored local files under `Unity/Assets/LostCity274` and `Unity/Assets/Scape/Resources`; neither a Unity editor nor a remote asset server is needed. The staging output must be outside the source checkout. The copy preserves other resources.

`AssetPack/`, `Icons/` and `Feedback/` under `Native/TableScape/Resources` are intentionally ignored. The pack contains **10,885 files / 10,394,320 payload bytes**, including **4,556 models and 50 textures**. Small-file disk allocation is larger than payload size. Terrain and animation sequences come from the gateway asynchronously.

The build verifies every file and requires the manifest to match `Native/AssetPack.lock`. Do not change the lock to bypass an error. An intentional asset update requires reviewing the regenerated manifest and lock together. The small checked-in lighting-definition lookup is already generated; ordinary builds do not need the original upstream definition checkout.

See [asset setup](../docs/ASSETS.md) for converting separately supplied upstream assets. Original models and artwork are not distributed in Git.

## Build and run

```sh
bash scripts/build-native-visionos.sh simulator
```

This checks storage and assets, mirrors the Metal source into its runtime resource, generates `Native/TableScape.xcodeproj` from `Native/project.yml`, and builds with simulator ad-hoc signing. Products and caches go under `$SCAPE_BUILD_ROOT`; logs and UI result bundles go under `$SCAPE_WORKSPACE/Artifacts`. Edit `project.yml`, not the generated Xcode project.

For live play, configure a trusted SSH alias for your server. The gateway must already be running on server loopback port 8890:

```sh
export SCAPE_SSH_HOST='your-configured-ssh-alias'
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$SCAPE_SSH_HOST" true
bash scripts/run-native-simulator.sh --tablescape-user=unitynative --tablescape-volume
```

The launcher reuses a healthy Mac loopback tunnel on port 18890 or opens one to the configured SSH host, verifies gateway revision 274, selects/boots a visionOS simulator, installs the app and launches it. It does not deploy the server or expose a public listener. An existing local forward can also supply the gateway without an SSH host setting.

**Rebuild after source/asset changes:** the launcher only builds when the app product is absent. A saved endpoint can override the simulator default; use `http://127.0.0.1:18890` in connection settings for this tunnel. Use a separate `unity`-prefixed development character for tests.

Other presentations:

```sh
bash scripts/run-native-simulator.sh --tablescape-immersive
# With neither presentation flag, use the main Metal preview window.
bash scripts/run-native-simulator.sh
```

For direct Xcode builds, configure Derived Data, package checkouts, module caches and temporary output under the configured build root first. The app's existing bundle identifier is `com.innoiso.tablescape.native`; retaining it preserves installation and Keychain continuity.

## Play

- **Open table window:** actual RealityKit geometry in a system volume; use system move/resize controls. Pinch terrain to walk or a target for actions. The player stays centered, and render/input transforms follow zoom and rotation.
- **Use real table:** immersive stereo Metal rendering with ARKit placement. Select/confirm a detected surface or mark four corners. The Simulator uses an explicit virtual table. Physical detection, tracking recovery and comfort still require headset checks.
- The icon toolbelt remains visible. Select a tab to open its panel; select it again to collapse. **Table controls** includes zoom, **Rotate 90°**, placement and **Leave table**.
- Inventory fits 28 icon slots. Skills and spells use original icons with details on demand. **More tools** provides Explore (Nearby and Messages), Map and other panels. Target options, conversations, game interfaces and amount entry use separate windows.
- Settings provides server-backed audio choices, Run and Auto-retaliate; legacy desktop preferences live in **Classic client**.
- Disconnect logs out and removes the game bearer. Session credentials use endpoint/character-scoped Keychain storage; diagnostic reports do not include credentials.

The volume is a shared-space window, while the mixed immersive scene requests Environment coexistence. System-window manipulation, gaze/pinch comfort and Environment behavior must be verified on actual hardware.

## Physical Vision Pro

```sh
bash scripts/build-native-visionos.sh device
```

This is an **unsigned device compile check**, not an installable delivery. Open the generated project, select your development signing team and paired Vision Pro, and build/run with Xcode output kept on the configured disk. Device provisioning is separate from simulator entitlements and ad-hoc signing.

A headset cannot use the Mac's loopback address. Follow [NETWORKING.md](NETWORKING.md) for an authenticated private HTTPS bridge, your own certificate identity, and manual or app-scoped CA trust. Do not commit private keys, bridge credentials or `PrivateConnection.json`. Complete the [physical acceptance sequence](PLAN-ACCEPTANCE.md#physical-acceptance-sequence) on hardware.

## Verification

With the same storage environment and prepared assets, run offline checks:

```sh
bash Native/TableScape/Spatial/check-geometry.sh
bash scripts/test-native-render.sh
bash scripts/test-native-volume.sh
bash scripts/test-native-volume-input.sh
bash scripts/test-native-model-audit.sh
bash scripts/test-native-model-gpu-lighting.sh
bash scripts/test-native-performance.sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-native-private-bridge.py
python3 scripts/audit-repository.py
```

For a running gateway and booted Simulator:

```sh
bash scripts/native-assets-check.sh
bash scripts/test-native-core.sh
bash scripts/test-native-ui.sh
```

Live suites create fresh QA characters and log out the sessions they own. [Tests/README.md](Tests/README.md) documents focused suites and coverage; [PERFORMANCE.md](PERFORMANCE.md) describes timing limits. Profiling with `--tablescape-profile` writes bounded `Documents/profile.json` in the app container. The in-app `--tablescape-test` mode writes `Documents/playtest.json`. Export results to your configured artifact directory; local reports and screenshots are not repository inputs.

Recorded checks include all **4,556 models / 615,847 faces**, representative cow/goblin/textured-model GPU comparisons, simulator gameplay, table controls, settings and combat feedback. A signed device build installed successfully, but the last automatic launch was unconfirmed. Mac GPU tests and simulator timing are not physical headset appearance or frame-rate proof. See [PLAN-ACCEPTANCE.md](PLAN-ACCEPTANCE.md) for outstanding hardware and parity work.
