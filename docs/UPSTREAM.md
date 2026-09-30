# Upstream dependencies and storage

The current playable target is LostCityRS revision 274. The original game client is used only as an asset decoder/reference; gameplay runs in Unity or the native Swift visionOS client. Both use the shared gateway; the native client does not require the Unity editor.

| Local checkout under `vendor/` | Upstream | Pinned revision |
|---|---|---|
| lostcity-engine274 | https://github.com/LostCityRS/Engine-TS | 1d25566cb53e7af1b1cb18ade8af996316c19614 |
| lostcity-content274 | https://github.com/LostCityRS/Content | 65b754f768b79b941b21b2a1eb3b0d1ecae3cdfe |
| lostcity-client274 | https://github.com/LostCityRS/Client-TS | 7d6ca61abda277cfed87d542e9e4aa3fe383b38d |

The engine's local changes are preserved in `integration/lostcity274/engine-local-setup.patch`. Authored gateway code is in `integration/lostcity274/unity/`; `install-unity-gateway.sh` copies it into the engine checkout. The local world settings template is `integration/lostcity274/world.json`. Vendor dependencies must be checked out and installed separately; this repository is not a complete machine image or a one-command fresh-machine installer.

`assets/UnityAssets.lock.json` pins checksums for separately supplied local assets. See [asset setup](ASSETS.md) for import/conversion. LostCity's MIT license covers its software, not the original Jagex assets. Original terrain triangulation source retains its upstream software license under `integration/lostcity274/unity/UPSTREAM-LICENSE.txt`. Models, sprites, fonts and generated audio remain outside Git.

Install the engine's pinned dependencies separately, including Node 24 and generated game data. Configure your own server paths and environment; this repository is not a complete machine image or a one-command backend installer. The unit files in `service/units/` are templates: replace `/path/to/scape-tabletop`, create your user service environment file outside Git, and review them before installation. `install-unity-gateway.sh` copies the gateway into the configured checkout and restarts the corresponding user service; run it only when intentionally updating that server.

Unity requires an activated editor 6000.0.73f1 and the official CLI, supplied through `SCAPE_UNITY_EDITOR` and `SCAPE_UNITY_CLI`. The native client requires neither. See [native setup](../Native/README.md) and [Unity setup](../Unity/README.md) for the two build paths. Backend credentials, runtime configuration, save data and machine-specific deployment notes stay outside Git.
