# Revision 274 parity work

The target is playable LostCityRS revision 274 in a native Unity client. This is a substantial gameplay integration, not complete original-client parity. There is no dependency on a running original Java or browser client.

## Implemented transport and client paths

| Area | Current implementation |
|---|---|
| World | Original terrain with blended underlay colours and height lighting; 16-tile retained chunks in a 7×7 neighbourhood on the active floor and floors below; interactive scenery plus noninteractive cache walls/fences; original hillskew vertex contouring for terrain-following scenery; NPCs, items and neighbouring players |
| Movement | Server collision/pathfinding, running, interpolated actor movement, object approach routing |
| Appearance | Original model assets, equipment slot replacement, identity kits and recolours; character design selection |
| Animation | Original cache sequences and transforms, interpolated frame poses and short sequence transitions; corrected actor facing and preserved action events |
| Camera/map | Smoothed follow/orbit/zoom; arrow keys and right-drag orbit; north-up rendered minimap with actor dots and click-to-walk |
| Interaction | Hover action/name/combat-level labels, right-click world action menus, Examine descriptions, original click-cross feedback; five scenery/NPC/player/ground-item/held-item operations; item use and spell targeting on each target type |
| Combat feedback | Preserved server damage events, original block/damage/poison hit-splat sprites and overhead health bars; duplicate events suppressed per entity |
| Audio/effects | Original MIDI music and jingles rendered with the Lost City soundfont; original synthesized sound bank; server-driven attached/ground spot effects and projectiles using cache models, recolours and animation frames; native volume controls |
| Interfaces | Original floating quest-completion overlays with original fonts/models/layout and live reward data; original icon tabs, sidebar frames/bitmap fonts/layouts, skill/prayer/spell grids, live tooltips and active states; dialogue, choices, amount entry, close/logout |
| Inventory | Original item/equipment icons and quantities, inventory context menus, held actions, equipment removal, shop/bank operations, inventory selection and item targeting |
| Multiplayer | Separate local native sessions, neighbouring avatars, player operations, correctly sourced trade offers and two-stage trade confirmation |
| Build | Unity CLI Linux builds, SSD storage guard, native rendering and gameplay smoke tests |

These routes make existing server scripts accessible. An implemented route does **not** prove every quest, skill, item or interface that uses it works correctly.

## Verification

The September 27 broad native audit records baseline XP evidence for every enabled skill and additional recipe, prayer, quest, banking, shop, trade, food and rejection scenarios. See [the recorded results](Saved/playtests/PLAYTEST_RESULTS.md) and [coverage limits](tests/COVERAGE.md). These runs use disposable fixture characters; supplied items and levels are prerequisites, not gameplay passes. The native Unity client performs the tested actions through normal original server handlers. The trade peer is a separate protocol test session, not another rendered Unity client.


`Saved/unity-parity-gameplay.log` records an actual Unity player test. It joins Tutorial Island (or resumes its local test save), follows normal dialogue to Lumbridge, changes equipment, drops and picks up an item, cuts a tree for logs/XP, and uses a tinderbox for Firemaking XP. It records animation frame processing and captures `Saved/unity-parity-gameplay.png`.

Additional gateway tests have exercised:

- Original animation data and changed equipment model IDs.
- Woodcutting and item-on-item Firemaking, with inventory and XP assertions.
- Wind Strike, rune consumption and Magic XP.
- General-store sale yielding coins and purchase yielding an item.
- Two simultaneous sessions with mutual player visibility.
- Bank-booth opening, item deposit, withdrawal and Withdraw X amount entry.

The earlier tests above used normal gameplay, including the development server's tutorial-skip dialogue. The current default startup deliberately teleports local test characters to Lumbridge at the user's request. New characters use the original tutorial-completion script; existing inventory, bank and stats are preserved. Legacy gateway regression scripts explicitly set `startLumbridge: false` to retain their prior starting conditions. No staff rights are granted.

## Known gaps and next parity work

- Complete original presentation for remaining main interfaces, chat and minimap framing; full client-only control behavior and animated/dynamic model previews. Original sidebar icons, item icons, inventory context menus and representative interactions are now verified.
- Complete animation fidelity: exact integer rounding, attachment transforms, animation override equipment, and all transient events.
- Exhaustive projectile/spot-effect coverage, overhead chat and full combat presentation. Wind Strike, Lumbridge teleport and Prayer level-up effects now have native coverage.
- Exhaustive music/sound coverage and exact transition/timing fidelity; public/private chat, friends/ignore controls and original account/login protocols.
- Complete scenery lighting/shadows, all scenery shapes, translucency, complete roof-hiding rules, other upper-floor/bridge cases and morphing definitions. Ground, lower scenery and the full gnome-course floor transitions now have native coverage.
- Exhaustive quest/skill/area coverage, trade failure paths/dueling, character design and advanced inventory actions.
- Broader physical input testing beyond the Lumbridge suite, production networking/security, performance profiling and AVP/visionOS interaction/build verification.

The gateway is intentionally loopback-only and supports development names beginning with `unity`. It is not an internet game service or an official RuneScape login client.

## Repeat tests on game server

```sh
cd $SCAPE_SOURCE_ROOT
bash scripts/build-unity-client.sh
python3 integration/lostcity274/unity/test_parity.py
python3 integration/lostcity274/unity/test_multiplayer.py
bash scripts/test-unity-gameplay.sh
bash scripts/test-unity-rendering.sh
bash scripts/test-unity-feedback.sh
bash scripts/test-unity-lumbridge.sh
```

`test_parity.py` creates a disposable local character. The exploratory bank/shop scripts retain test-save/location assumptions and are not general regression tests. The native test uses the persisted `unityplay` character. Tests change those test characters' normal game state.

## Rendering regression test

`--scape-render-test` resumes the local `unityplay` character, waits for 49 terrain chunks, counts restored static walls and textured ground batches, walks using a normal server action, checks model facing, samples camera motion and captures the native player. The minimap uses original world geometry, with north up; click to walk. Arrow left/right orbit, arrow up/down tilt, right-drag orbits, and the wheel zooms. Lower-floor terrain and scenery are retained during upper-floor traversal; exact roof-hiding rules and original shadowing remain incomplete.

## Combat and interaction feedback

The feedback test uses the normal NPC Attack option against a nearby Man or Goblin with the persisted local test character. It checks actual server damage reception, overhead bar/hit-splat drawing, NPC and scenery menu contents, hover labels and click markers. It captures `Saved/unity-feedback.png`. This exercises menu action dispatch and native rendering; physical mouse input remains a manual test. Right-click without dragging opens the menu; a drag of more than five pixels retains camera orbit. Click crosses indicate queued actions, not a guarantee that an action succeeded; game messages and rejection notices carry the result.

## Lumbridge usability and input playtest

The native Lumbridge test creates a fresh disposable local character, checks its default spawn, and uses X11 mouse input in an isolated Xvfb display to open Hans's right-click menu, choose Talk-to and click Continue. It checks dialogue text and choices, presses the right arrow to verify the reversed camera direction, and opens/closes the outer castle doors before dropping and picking up an inventory item through normal server actions. Captures and input logs are saved under `Saved/unity-lumbridge*`. The UI now uses opaque brown panels, a flat option menu and a separate parchment-coloured conversation panel. Original sidebar fonts, sprites and inventory icons have since been restored; Animated original dialogue portraits have since been added; other chat presentation details remain unfinished.

## Terrain-following scenery

The gateway exports the original `hillskew` flag as four cache-height samples. Unity applies the revision 274 vertex-height adjustment after model transforms, including mirrored fence parts, and updates each instance’s mesh bounds and picking collider. Unflagged scenery and shared asset meshes stay unchanged. `bash scripts/test-unity-slopes.sh` loads native Lumbridge scenery, compares rendered vertices with an independent bilinear reference, and captures a sloped fence with and without contouring.

## Connection recovery

Native sessions now recover from a 401 with one bounded reconnect loop. Automatic reconnects retain the saved location rather than applying the default Lumbridge teleport again. Temporary transport/server failures pause interactions, clear queued clicks and retry state reads with backoff; uncertain actions are never automatically resent. After five failed attempts the client presents a manual reconnect control. Invalid game/session responses produce a readable error instead of raw HTTP/JSON text. Logout cancels recovery, invalidates outstanding callbacks, and releases late-created sessions. The gateway identifies closed sockets as expired sessions.

`bash scripts/test-unity-sessions.sh` tests a real server session invalidation and uses an isolated loopback proxy for outages, malformed replies and a delayed login. The normal desktop client continues to connect directly to the gateway.

## Original audio and transient effects

`bash scripts/prepare-unity-media.sh` extracts 345 original MIDI files and decodes 912 sound definitions on the game server WD SSD. The original TinyMidi PCM renderer and bundled SCC1 Florestan soundfont synthesize music; the original JagFX decoder synthesizes sound effects. Authenticated audio requests render/cache WAV files on demand without blocking the gameplay tick. Unity plays region music, jingles and sound events with native volume controls synchronized to the original settings sidebar.

Original server spot-animation and projectile events now carry model/recolour/sequence data into Unity. Actor effects follow their actors; projectiles use target tracking and ballistic motion. Duplicate events are suppressed and logout/recovery clears transient media. Tutorial tab acknowledgements now match the original flashing-tab condition, preventing completed accounts from reopening the tutorial overlay.

`bash scripts/test-unity-media.sh` uses a disposable fixture character through normal spell and inventory handlers. See [the native media report](Saved/media/RESULTS.md). Fixture prerequisites are not counted as gameplay results. The test requires the temporary `SCAPE_TEST_FIXTURE_DIR` setup described in the report. This establishes representative native playback and effect rendering, not exhaustive sound, spell or area parity.

## Original quest-completion overlays

Questscroll reward interfaces now float over the Unity world using their original layout, bitmap fonts, scroll/rosette and dynamic reward models. Original server text and point totals update live. Close Window and Escape dismiss the modal, and its area blocks world picking. The native Cook's Assistant completion, physical close click, journal and unlocked range all passed; see [overlay results](Saved/overlays/RESULTS.md). Other main interfaces retain their existing renderer.

## Original sidebar menus and item icons

All 13 enabled tabs now use original iconography, frames, bitmap fonts and component layouts. Prayer/spell active artwork and original tooltips update from the server state; inventory and equipment use original item icons and operations. The final native mouse-input suite passed 43 checks with zero missing icon lookups. Banking, shops, Cook’s Assistant and the physical Lumbridge regression also passed. See [sidebar results and limits](Saved/sidebar/RESULTS.md). Run `bash scripts/test-unity-sidebar.sh` with temporary QA fixtures configured as documented there.

Menu textures now retain their exact source dimensions; the original frame join is restored, eliminating the observed see-through gaps. The expanded sidebar suite passed 54 checks, including visible Lumbridge General Store stock and real mouse Buy/Sell actions with inventory/coin assertions. See [frame and shop results](Saved/menu-dimensions/RESULTS.md).

## Animated dialogue portraits

The server's NPC/player-head and animation updates now drive original head meshes, recolours and facial sequences in the native chat panel. NPCs appear on the left and player replies on the right; choices and closed dialogue clear portraits. The native Hans conversation suite passed 16 checks, including visible pixels, changing animated vertices, speaker switches, closing, reopening and logout. See [chat-head results and limits](Saved/CHATHEAD-RESULTS.md). Run `bash scripts/test-unity-chatheads.sh` after the normal CLI build.

## Death animations and command access

Death playback now preserves server-issued terminal updates across NPC removal, waits for real animation frames and recognizes the original long final-pose hold. Native NPC kill/bones pickup/tree chopping and player death/respawn scenarios passed. The running browser Unity client now has a private local command interface for exact nearby targets, inventory/actions, widgets, camera and state inspection. See [results and coverage limits](Saved/DEATH-CONTROL-RESULTS.md) and [client control commands](docs/CLIENT_CONTROL.md).
