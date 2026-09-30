# TableScape

A tabletop client for LostCityRS revision 274, with a **native Swift/Metal client for Apple Vision Pro** and a **Unity client for Linux and Quest development**. Both use the same private game gateway and separately supplied original assets. A running browser or Java game client is not required.

| Client | Rendering | Setup |
| --- | --- | --- |
| Native visionOS | Metal/MetalKit preview and minimap; stereo Metal through Compositor Services with ARKit placement; separate RealityKit 3D table window and SwiftUI controls | [Native setup](Native/README.md) |
| Unity | Original models, animation and server-backed desktop gameplay; Quest tabletop development | [Unity setup](Unity/README.md) |

## Native setup

Requires an Apple silicon Mac, full Xcode with the visionOS 26 SDK and Simulator runtime, XcodeGen, Python 3.10+, Git and ripgrep. Unity is not required for the native build.

Choose an existing mounted development disk. Paths and SSH identities are operator configuration; the repository does not supply a particular machine, storage mount, account or server address. Keep the checkout and generated output on that disk.

```sh
export SCAPE_STORAGE_ROOT='/path/to/mounted-development-disk'
export SCAPE_WORKSPACE="$SCAPE_STORAGE_ROOT/TableScape"
# Replace the placeholder above with your actual mounted disk before continuing.
python3 -c 'import os; p=os.environ["SCAPE_STORAGE_ROOT"]; assert os.path.ismount(p) and p != "/", "Choose an existing development-disk mount"'
mkdir -p "$SCAPE_WORKSPACE"
git clone --branch main \
  https://github.com/innoiso/tablescape.git "$SCAPE_WORKSPACE/Source"
cd "$SCAPE_WORKSPACE/Source"

# Supply a separately converted asset set; see docs/ASSETS.md for conversion.
python3 scripts/import-game-assets.py --from-unity-assets \
  '/path/to/existing/TableScape/Unity/Assets'
# Generate ignored native resources from the verified local assets.
python3 scripts/native-assets.py build --source "$PWD" \
  --output "$SCAPE_WORKSPACE/Assets/revision274-v1"
rsync -a "$SCAPE_WORKSPACE/Assets/revision274-v1/" Native/TableScape/Resources/
bash scripts/build-native-visionos.sh simulator
```

Original game assets are not distributed in this repository. See [asset setup and rights](docs/ASSETS.md). The native asset pack contains 4,556 models, 50 textures, icons and feedback artwork: about 10.4 MB of payload. The build verifies every file and the pinned `Native/AssetPack.lock`. Generated resources, Xcode projects, build products and caches are excluded from Git. Apple-managed simulator data and tools still occupy system storage.

For connected play, provision the [shared gateway](docs/UPSTREAM.md) on your own server and configure a trusted SSH alias for it. The launcher reuses a healthy Mac loopback tunnel or opens one to the configured server's loopback gateway. It does not install the server.

```sh
export SCAPE_SSH_HOST='your-configured-ssh-alias'
# Rebuild after pulling source changes; the launcher reuses an existing app.
bash scripts/build-native-visionos.sh simulator
bash scripts/run-native-simulator.sh --tablescape-volume
# Alternative: immersive Metal/ARKit mode.
bash scripts/run-native-simulator.sh --tablescape-immersive
```

See the [native guide](Native/README.md) for tool checks, signing, tests and troubleshooting, and [private networking](Native/NETWORKING.md) for a physical headset's HTTPS connection.

## Gameplay and verification

The persistent toolbelt opens inventory, skills, spells and compact settings; selecting the active icon collapses its panel. Table controls provide zoom and 90-degree rotation. Nearby targets and messages live in Explore; actions, dialogue and the map have separate windows. The player stays centered, lower terrain remains visible, and original-model lighting and hit-splat transparency are preserved.

The recorded native checkpoint includes simulator gameplay/UI checks, an audit of all 4,556 models, and actual Mac GPU comparisons of cow, goblin and textured models. A signed build was installed on Vision Pro; physical placement, input, Environment coexistence and sustained headset performance still require acceptance. See [native test coverage](Native/Tests/README.md), [performance](Native/PERFORMANCE.md), and [plan acceptance](Native/PLAN-ACCEPTANCE.md). Complete original-game parity is not claimed.

## Unity client

The Unity client uses editor 6000.0.73f1 and the official Unity CLI. Configure their executable paths and the mounted storage location as described in [Unity/README.md](Unity/README.md), then run from the checkout:

```sh
python3 scripts/import-game-assets.py --from-unity-assets \
  '/path/to/existing/TableScape/Unity/Assets'
bash scripts/verify-unity-assets.sh
bash scripts/build-unity-client.sh
bash scripts/run-unity-client.sh
```

The default local development character is `unitytest`. Use separate `unity`-prefixed test names for automated checks. These are local game characters, not official RuneScape credentials. The gateway listens on server loopback port 8890; keep it private. [Gameplay coverage](PARITY.md) describes verified features and gaps. [Browser testing](docs/BROWSER-TESTING.md) explains optional streaming of the native Unity client.

## Repository contents

- `Native/`: native Swift app, Metal shaders, RealityKit rendering, ARKit placement and regression tests.
- `Unity/Assets/Scape/`: Unity gameplay, rendering and import/build tools.
- `assets/UnityAssets.lock.json`: checksums for separately supplied local game assets.
- `integration/lostcity274/`: shared gateway and pinned upstream integration.
- `scripts/`: configurable asset, build, launch and test tools.
- `service/units/`: service **templates**; configure paths/environment before installing.
- `Source/` and `ScapeTabletop.uproject`: superseded same-project Unreal prototype, described in [historical notes](HISTORICAL-PROTOTYPE.md).

Private deployment notes, local reports, credentials, player saves, vendor checkouts and generated output are excluded. Upstream software notices remain in place; Jagex game assets are not covered by those software licenses. The existing app identifier is retained so updates preserve installed app data and Keychain scope.

## License

TableScape-authored source code and documentation are licensed under the [MIT License](LICENSE). Third-party code retains its original copyright and license notices, including the [Lost City software notice](integration/lostcity274/unity/UPSTREAM-LICENSE.txt).

This license does not cover separately supplied RuneScape/Jagex game assets, artwork, fonts, audio, or trademarks, and grants no rights to redistribute them. See [asset provenance and setup](docs/ASSETS.md).
