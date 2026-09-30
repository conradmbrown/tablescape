# Project direction

- Preserve both clients: Unity and the native Swift/Metal/ARKit/SwiftUI visionOS client in `Native/`.
- Use original LostCityRS revision-274 assets and the shared game gateway. Do not substitute a running browser/Java client or the historical Unreal viewer for native gameplay.
- Source, builds and caches must stay on the operator-configured mounted development disk. Source `scripts/storage-env.sh`; never invent a mount directory or embed workstation paths, hosts, accounts or private network addresses.
- Unity editor batch work uses the official Unity CLI and editor 6000.0.73f1. Configure executable paths through the documented environment variables.
- Native setup is in `Native/README.md`; private device transport is in `Native/NETWORKING.md`. Import separately supplied originals following `docs/ASSETS.md`; never track original game assets. Rebuild ignored native resources with `scripts/native-assets.py` and verify `Native/AssetPack.lock`.
- Keep private configuration, credentials, generated reports, local saves and code from unrelated projects out of Git. Run `scripts/audit-repository.py` before publication.
- Preserve unrelated working changes. Do not rewrite published Git history without explicit authorization.
- Keep build, automated test, simulator, installation and physical-device acceptance distinct. Never claim full gameplay or visual parity from source alone.

For live Unity control, read `docs/CLIENT_CONTROL.md`. `scripts/remote-client.command` uses the operator's SSH alias and remote checkout path; `scripts/client-control.py` can run directly on the server. Automated fixtures must use a separate fresh QA character and control directory, never the user's active character. Verify authoritative game state after a queued action.
