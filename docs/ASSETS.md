# Local game assets

This repository distributes client/integration code and asset checksums, **not original game assets**. Builds need a separately supplied revision-274 asset set. All imported models, textures, sprites, fonts and generated runtime packs are ignored by Git. Keep them on the configured development disk.

Upstream: [LostCityRS/Content](https://github.com/LostCityRS/Content), commit `65b754f768b79b941b21b2a1eb3b0d1ecae3cdfe`. LostCity states that its source code is MIT-licensed but the game assets belong to Jagex and are **not covered by that license**. See [the upstream notice at the pinned revision](https://github.com/LostCityRS/Content/blob/65b754f768b79b941b21b2a1eb3b0d1ecae3cdfe/README.md). Obtain and use assets only with the applicable rights; this project does not grant redistribution rights. A copied upstream `LICENSE.txt` concerns upstream software, not the artwork.

## Import an existing converted set

An existing TableScape installation has the converted set under `Unity/Assets`. It must include `LostCity274/` and `Scape/Resources/{Icons,Feedback,Overlays}/`. Do not copy its Git directory, credentials, saves, or other source files.

Configure `SCAPE_STORAGE_ROOT` and `SCAPE_WORKSPACE` as in the root README. From the new checkout:

```sh
python3 scripts/import-game-assets.py \
  --from-unity-assets '/path/to/existing/TableScape/Unity/Assets'
python3 scripts/import-game-assets.py --verify
python3 scripts/native-assets.py build --source "$PWD" \
  --output "$SCAPE_WORKSPACE/Assets/revision274-v1"
rsync -a "$SCAPE_WORKSPACE/Assets/revision274-v1/" Native/TableScape/Resources/
```

The importer checks every expected file against `assets/UnityAssets.lock.json` **before copying anything**. It copies only the locked asset payloads into ignored locations and verifies the result. Unity regenerates its `.meta` files locally. The native pack must match `Native/AssetPack.lock`; missing or modified assets are rejected. Existing local assets can be verified in place with `--verify` without another copy.

## Convert from upstream sources

This is a conversion workflow for an already provisioned revision-274 development setup, not a backend installer. Use the pinned Content, Engine-TS and Client-TS revisions in [UPSTREAM.md](UPSTREAM.md). Place separately obtained sources in the ignored directories `vendor/lostcity-content274`, `vendor/lostcity-engine274`, and `vendor/lostcity-client274`. Install the pinned upstream dependencies and generate the engine's `data/pack` with the upstream build instructions. Use Node 24. The overlay exporter needs the engine's `tsx`/`esbuild` dependencies and packed title, media, config, textures and interface data. It does not need a running game server or Unity editor.

From the TableScape checkout:

```sh
python3 scripts/prepare-unity-assets.py \
  --content "$PWD/vendor/lostcity-content274" --project "$PWD/Unity"
bash scripts/prepare-unity-overlays.sh
python3 scripts/prepare-unity-feedback.py --content "$PWD/vendor/lostcity-content274"
python3 scripts/import-game-assets.py --verify
```

These steps copy numeric original model/texture IDs, export original bitmap fonts and interface sprites, render item/component icons with the original client renderer, and copy combat feedback sheets. Export all overlays; do not use the partial `--sprites-only` or `--textured-items-only` options for initial setup. Then generate/copy the native pack using the commands above.

The locked importer/native pack workflow is verified independently of server provisioning. A fresh upstream backend installation and its data-packing process must be completed using upstream documentation; they are not automated here. Hash mismatches must be investigated (wrong revisions, missing exports, or altered images), never bypassed by casually updating the lock.

Audio is optional for asset preparation and supplied by the private gateway: after provisioning its dependencies, `bash scripts/prepare-unity-media.sh` generates the ignored audio cache. Do not include generated audio or other game assets in source releases.

## Storage and release checks

Asset sources, `Saved/` conversion intermediates, imported Unity resources and native packs stay local. The native pack has about 10.4 MB of payload; upstream dependency/build caches need additional space. No backend is downloaded or started by the importer.

Before committing, run `python3 scripts/audit-repository.py`. It rejects tracked game-asset payload paths as well as private credentials/output. The committed locks contain file paths, sizes and hashes only. Do not force-add ignored assets or attach asset packs to GitHub releases.
