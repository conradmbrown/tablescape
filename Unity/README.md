# Unity client

Playable LostCityRS revision-274 client. The native visionOS client is separate and does not require Unity; see [native setup](../Native/README.md).

## Configure and build

Install and activate Unity **6000.0.73f1** and the official Unity CLI. Clone this repository onto your mounted development disk. Set paths for your own installation:

```sh
export SCAPE_STORAGE_ROOT='/path/to/mounted-development-disk'
export SCAPE_WORKSPACE="$SCAPE_STORAGE_ROOT/TableScape"
export SCAPE_UNITY_EDITOR='/path/to/Unity/Editor/Unity'
export SCAPE_UNITY_CLI='/path/to/unity-cli'
# Run from the repository checkout on that disk:
python3 scripts/import-game-assets.py --from-unity-assets \
  '/path/to/existing/TableScape/Unity/Assets'
bash scripts/verify-unity-assets.sh
bash scripts/build-unity-client.sh
```

Build/runtime caches use `SCAPE_BUILD_ROOT` (default `$SCAPE_WORKSPACE/Build`). Guards reject missing mounts and paths outside the configured disk. The Linux product is `Builds/Linux/ScapeClient` relative to the checkout. Logs are local under `Saved/` and are not published.

See [asset setup and conversion](../docs/ASSETS.md). Original game assets are supplied separately and remain ignored by Git.

## Run

Provision the [pinned server dependencies](../docs/UPSTREAM.md) and gateway first. The default endpoint is `http://127.0.0.1:8890` on the server machine.

```sh
bash scripts/run-unity-client.sh
```

Default login uses local test character `unitytest` and places it in Lumbridge while preserving its inventory, bank and stats. Use another `unity`-prefixed name for independent playtests. Left click walks/interacts; right click opens options; right drag and arrow keys move the camera; the wheel zooms. [PARITY.md](../PARITY.md) records gameplay coverage and remaining gaps.

For a remote desktop stream, see [browser testing](../docs/BROWSER-TESTING.md). Quest tabletop work shares this client; a Linux build does not establish Quest or Vision Pro acceptance.
