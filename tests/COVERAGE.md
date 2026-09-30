# Revision 274 native Unity gameplay coverage

This is a coverage inventory, not a claim of complete parity. A successful baseline action does not cover every recipe, level bracket, quest gate, animation, or input path in a skill.

## Execution and evidence

`make_skill_suite.py` creates fresh `unityqa` characters and one-shot local fixture files. The backend must explicitly opt in with `SCAPE_TEST_FIXTURE_DIR`. Existing characters cannot consume fixtures. Fixtures supply prerequisites only. Native Unity performs actions through its normal selection/action code and the gateway's original packet handlers. Server-confirmed XP/material changes determine pass/fail; sending a command alone does not.

Each run records `results.json`, per-case before/after snapshots, screenshots, and `unity.log` on the WD SSD. These are automated native gameplay tests. They do not replace physical mouse/keyboard accessibility tests. The separate Lumbridge suite uses real X11 mouse/keyboard events for NPC context menus, dialogue continuation, hover, and arrow-key camera rotation.

## Skills

| Skill | Baseline scenario | Further coverage required |
|---|---|---|
| Attack | Accurate melee damage earns XP | All weapon types, accuracy, special attacks, level gates |
| Strength | Aggressive melee damage earns XP | Weapon styles, boosts, special attacks |
| Defence | Defensive melee damage earns XP | Armour bonuses, ranged defence, magic defence |
| Hitpoints | Combat damage earns HP XP | Food healing/cap covered; regeneration, poison, death and respawn pending |
| Ranged | Equip shortbow/arrows and damage NPC | Other bows, thrown weapons, crossbows, ammo recovery |
| Prayer | Bury bones | Drain rates, protection effectiveness, altar recharge (15 toggles covered by extended suite) |
| Magic | Wind Strike consumes runes and earns XP | Every combat/utility spell, autocast, teleports, enchanting |
| Cooking | Raw shrimp on a range | Fires, burning, recipes, bulk actions, level gates |
| Woodcutting | Chop tree; receive logs and XP | Higher trees, all axes, respawn and full inventory |
| Fletching | Feather arrow shafts | Logs and bow stringing covered; other arrows, bolts and darts pending |
| Fishing | Small-net shrimp | Rods, bait, fly fishing, harpoon, cage, spot movement |
| Firemaking | Tinderbox/logs creates fire and XP | Higher logs, blocked tiles, extinguishing |
| Crafting | Cut sapphire | Leather, pottery, glass, jewellery, spinning, battlestaves |
| Smithing | Smelt bronze | Bronze anvil selection and Smelt X covered; other products and metals pending |
| Mining | Mine low-level rock | Prospecting, all ores/picks, depleted rocks, respawn |
| Herblore | Identify guam; prepare and finish attack potion | Grinding, decanting, other herbs/potions, level gates |
| Agility | Gnome log balance | Other courses, failures, damage, shortcuts (complete gnome lap covered by extended suite) |
| Thieving | Pickpocket man | Failure/stun, stalls, chests, lockpicking, NPC levels |
| Runecraft | Bind essence at air altar | Other altars and multipliers (air talisman entry/portal exit covered by extended suite) |

The engine's `PlayerStatEnabled` disables slots 18 and 19. Slayer and Farming are not applicable to this revision and must not appear as playable skills.

## Other gameplay systems

| System | Coverage and outstanding work |
|---|---|
| Session recovery | Real 401 recovery, preserved progress, outages, malformed responses, bounded retries, manual reconnect and cancellation/late-login race covered in native Unity |
| Default start/save | Existing suite verifies Lumbridge start and retained inventory/XP on reconnect |
| World input | Existing actual-input suite verifies NPC right-click, Talk-to, Continue, hover, right arrow |
| Dialogue | Hans opening/choices covered; all NPC and quest branches still need coverage |
| Doors | Lumbridge outer castle open/close covered; original door texture substitutions (stone 2 → wood 0/4) and unchanged shared wall materials verified in native client; other door forms, ladders, stairs, gates pending |
| Original sidebar menus | All 13 enabled icon tabs and artwork checked; physical prayer toggles, spell tooltip/selection, equipment icons and inventory context-menu drop passed; exhaustive controls/social behavior pending |
| Inventory | Original item icons, equip/drop/pickup covered; full-inventory mining rejection and bank quantity input covered; splitting and rearrangement pending |
| Banking | Native deposit/withdraw-X scenario in skill suite; notes and all quantity modes pending |
| Shops | Native general-store buy/sell covered; physical Lumbridge General Store Buy 1/Sell 1 and visible stock now covered; price boundaries, restock and specialist shops pending |
| Combat feedback | Native damage splats, health bars and original sprite transparency tested earlier |
| Multiplayer | Native trade with a protocol peer covered separately; two-native-client rendering, follow, PvP and trade failure paths pending |
| Quests | Cook’s Assistant dialogue, ingredient hand-in, reward, journal and range unlock covered with fixture ingredients; natural ingredient gathering and other quests pending |
| Minigames | Not certified |
| Friends/ignore/chat | Not certified |
| Audio | Native Harmony music/mixer output, Wind Strike/teleport/bone-burying sounds, Prayer level-up jingle and music resume passed; 345 MIDI files and 912 sound definitions available, exhaustive playback not certified |
| Rendering | Original terrain/models/textures/chunks covered in earlier tests; gnome-course floor transitions covered; original hillskew terrain-following scenery now has a native mesh/collider regression; Wind Strike projectile, cast/impact, teleport and level-up spot effects covered; other upper floors, roof hiding, morphs, untested effects and exact lighting remain |
| AVP | Current verification is Linux Unity; visionOS/AVP interaction and performance remain |

## Findings fixed during this audit

- New-character Lumbridge setup now sets entry state before the original login trigger. Closing the original design interface previously queued a callback that reset tutorial progress to 1 and kept weapon controls locked to unarmed.
- Combat buttons use the original adjacent labels and display selected styles. Prayer buttons use original tooltip names and display the server's active state.
- Disabled stat slots no longer appear as Slayer/Farming or inflate total level.
- Upper-floor streaming retains lower terrain and scenery, with lower-floor colliders disabled to avoid selecting objects on another floor. Authoritative lower-floor interactive scenery is rendered separately.
- Inventory listeners now resolve their actual source player through the engine API, so a trade partner's offer is not replaced by your own offer. Offer panels are explicitly labelled.
- Native status displays the server's action-delay state. Tests wait for normal script delays instead of treating ignored early clicks as successful actions.

## Reproducing the suites

Use the authored scripts on game server under `$SCAPE_SOURCE_ROOT`; all runs, fixtures and Unity caches stay on that SSD. Generate fresh accounts with `tests/make_skill_suite.py RUN --fixtures FIXTURES`, enable the private backend's `SCAPE_TEST_FIXTURE_DIR` for that fixture directory, and run `scripts/test-unity-skills.sh RUN` after building through `scripts/build-unity-client.sh`. Fixtures are consumed once and reject existing saves. Remove the temporary fixture environment and restart the backend after QA.

`tests/native_trade_peer.py generate RUN --fixtures FIXTURES` prepares a native trade scenario and a disposable protocol peer. `scripts/test-unity-trade.sh RUN` runs one native Unity client against that peer. It verifies the distinct partner offer and the transfer in both directions. This is not a two-native-client rendering test.

`tests/report_skill_suite.py RUN... --output OUTPUT` retains prior failures in its JSON history, lists the latest result per case, and reports XP evidence separately from action dispatch. `scripts/test-unity-lumbridge.sh` is the real mouse/keyboard regression suite.

The media suite and evidence are documented in `Saved/media/RESULTS.md`. Ordinary tab changes now send tutorial acknowledgements only for the server-requested flashing tab; native QA checks that completed characters keep the tutorial closed.

The original floating quest reward presentation now has a native Cook's Assistant run with eight passing gameplay checks, original model/font loading, live award/total points, and a real mouse click on Close Window. See `Saved/overlays/RESULTS.md`. This does not certify all quest reward variants or convert all other interfaces.

The original sidebar suite passed 43 checks, including physical icon clicks, prayer state, spell hover/selection and inventory context-menu actions. The selected spell also earned server Magic XP through normal targeting. There were zero missing icon lookups across all 13 enabled tabs. Banking/shop/quest regressions passed 15 checks and the Lumbridge physical-input suite passed. See `Saved/sidebar/RESULTS.md` for screenshots, fixture prerequisites and remaining presentation limits.

The menu-dimension follow-up passed 54 native checks, including source-size preservation and physical general-store purchase/sale. This closes the prior gap between direct shop action tests and visible shop menu interaction. See `Saved/menu-dimensions/RESULTS.md`.

Animated dialogue portraits: `scripts/test-unity-chatheads.sh` passed 16 native checks through Hans's greeting, choice, player reply, NPC reply, close/reopen and logout. It measures rendered portrait pixels and changing animated vertices. No fixture is needed. This covers one NPC and the default player appearance, not all head/animation/equipment combinations. See `Saved/CHATHEAD-RESULTS.md`.

Native command access and death lifecycle: `scripts/test-client-control.sh` passed NPC death through its final pose, bones pickup and exact-tree chopping with logs/25 displayed Woodcutting XP. `SCAPE_CONTROL_SCENARIO=player-death scripts/test-client-control.sh` passed observed death frames and normal respawn. Disposable prerequisites are excluded from gameplay achievements. See `Saved/DEATH-CONTROL-RESULTS.md`.

Door texture verification (2026-09-27): native Lumbridge suite passed all 15 checks,
including texture 2 → 0 on door 1530 and 2 → 4 on door 1536, preserving the shared
model-634 stone material. Live native commands opened the south gatehouse door at
3226,3214 (1530 → 1531 at 3227,3214), then closed it back to 1530. Native frame
captures verified the original wood on the open leaf and both sides of the closed
leaf. Castle double-door open/close also passed. No missing replacement texture
errors occurred in either client log. Browser stream rebuilt and restarted.

Scenery shading verification (2026-09-27): original model topology is retained for
shared vertex normals and flat face flags. Untextured scenery faces use revision
274 normal accumulation, ambient/contrast and HSL lightness after recolouring;
textured faces retain their existing texture materials. Both Lumbridge king
statues (loc 563, model 1527) passed a native check for lightness variation within
the same stone colour (61) while remaining opaque. Before/after native captures
and opposite camera angles were inspected. All 16 Lumbridge checks passed,
including the door wood substitutions, open/close, dialogue, camera and item
pickup. Asset verification passed for all 4,556 imported models.

Diagonal wall-decoration verification (2026-09-27): diagonal shapes 6/7/8 now
carry the original 45/225-degree face rotations and 53/-45 cache offsets. Shape 8
renders both wall faces. After chunk assembly the native client seats each
backing on the matching diagonal wall mesh, compensating for the original
software renderer's overdraw of recessed decorations. The two southeast
Lumbridge arrow slits were inspected from outside and inside. Native regression
checks both faces, rotations and backing-to-wall separation below 0.003 tiles;
all 17 Lumbridge checks passed, including prior door and statue checks.

Context-menu replacement (2026-09-27): a right-button press dismisses the existing
menu and continues through targeting on that same click. The native X11 test
opens Hans's menu, right-clicks a tree without dismissing first, verifies Hans's
options are gone, then right-clicks Hans and selects Talk-to from the replacement
menu. Dialogue opens successfully. The test finishes approach movement before
choosing fixed screen coordinates; early moving-camera runs are preserved in
Saved/menu-retarget-first-run.log and Saved/menu-retarget-second-run.log. The
stabilized full Lumbridge run passed all 22 checks.

Movement timing (2026-09-27): `bash scripts/test-unity-movement.sh` logs native
frame positions and camera positions on a 20-tile Lumbridge walk and return run.
The client now buffers server-tick positions on a shared clock instead of
restarting interpolation at each response. Polling uses a 100 ms interval;
clock correction is bounded, stale/duplicate actor samples are ignored, large
teleports reset the track, and missing data stops at the last confirmed tile.
Walk/run selection uses tile displacement per server tick (including diagonal
walking), independent of rendered backlog. Original secondary animation delays
include the extra 20 ms cycle present in revision 274's entityAnim loop; primary
combat/death timing is unchanged.

With the browser client also running, before/after traces measured speed over
150 ms windows, excluding starting/stopping: walking position speed CV fell from
0.372 to 0.062, running from 0.358 to 0.093; camera CV fell from 0.278/0.275 to
0.067/0.103. The baseline had zero-speed windows; the updated trace had none.
Both routes reached server and rendered destinations with stable original
walk/run sequences 819/824. `scripts/check-movement-trace.py` enforces speed,
variation, pause and sequence checks on subsequent native runs. Deterministic
checks cover irregular arrivals, diagonal gait, running, stale samples,
connection stalls and teleport resets. This is native local-network testing,
not proof against arbitrary network outages or browser decode stalls.
The final build repeated the route with speed CV 0.064/0.072 (walk/run) and
camera CV 0.067/0.078, and passed all 12 facing checks. The separate fresh-account
native combat test passed with both actors facing each other, three received
hits, visible hit splats/health bars, menus, hover and click feedback.
All 22 physical-input Lumbridge checks also passed: replacement context menus,
Hans dialogue, camera arrows/hover, door opening/closing, dropped-item pickup,
and the existing statue/door/diagonal-decoration rendering assertions.

Interface context menus (2026-09-27): the new isolated fresh-account
`bash scripts/test-unity-context.sh` reproduced the inventory right-click failure
in the previous build (`Saved/unity-context-baseline.log`). IMGUI opened the menu
on mouse-down while world input dismissed open menus on that same press.
Inventory/shop and sidebar widget menus now open on right-button release, with
right-button presses consumed before underlying IMGUI buttons acquire them.
Menu rows receive left-button events before shop/sidebar controls, preventing
click-through. Shared menu placement/counting applies to both world and UI menus.
Sidebar widgets expose the original button option; targeted spells use the
original target verb and spell name, e.g. Cast Wind Strike, followed by Cancel.
The first updated native run passed inventory menu replacement/drop and displayed
all General Store Buy quantities, but its purchase was rejected with the server
message "You don't have enough coins." That trace is preserved as
`Saved/unity-context-unfunded.log`. The ordinary-account test now sells a starter
sword through the real Sell 1 menu to fund its purchase. No saved inventory or
backend fixture is modified. The unchanged production input fix passed all 22
physical-input Lumbridge checks, including NPC/object menu replacement and
selecting Talk-to from the replacement menu.
Cross-panel testing additionally caught UI gesture tracking depending on the
world camera's right-drag origin. UI gestures now retain their own IMGUI
press/release positions. The next native run confirmed starter sale, purchase,
return sale and all coin/item assertions. The spell-menu screenshot contained
the cache's original "Cast Wind strike" label; the test's initial title-case
comparison was corrected to accept the original casing without changing UI text.
Opt-in `--scape-context-test` logs press/release coordinates for diagnosis.
The final release build passed the complete context-menu suite: inventory menu
replacement and confirmed Drop; starter Sell 1 with coin gain; Buy 1 with exactly
one item gained and coins spent; Sell 1 returning the item count; shop close;
and spell right-click displaying Cast/Cancel without selecting prematurely,
followed by a real left-click selecting Wind strike. Native screenshots of the
shop and spell menus were inspected. The browser service uses this release build.

Skill animation and inventory texture repair (2026-09-27): health bars now use
recent server hits only; hover does not reveal an otherwise idle actor's bar.
The offline original item renderer now loads the cache texture archive, colour
tables and texel pool before drawing sprites. Previously textured faces were
omitted entirely, including log cut ends. Regenerated all 104 textured item icons
with zero export failures; native UI placement and browser scaling are unchanged.

Original sequence metadata now supplies weapon/shield replacements, both male
and female wear models, repeat-tail count, maximum repeats, duplicate behaviour
and movement cancellation. Temporary equipment shares the player's original
bone transforms and recolours, suppresses replaced equipment, and is removed
when the action ends. The backend retains animation events through their repeat
window. Authoritative tile movement cancels interruptible actions; buffered
render movement does not cancel an action just received from the server.
`UnityAnimationAudit.ts` checked all 1,363 cache sequences, including 265 with
hand overrides and 208 male/female model references: no imported models missing.
Ten gender/slot entries reference five original items that define no wear model;
these are recorded as source-data exceptions rather than invented replacements.

`test-unity-skill-animations.sh` adds native rendered-pose and held-model checks
to normal gameplay outcomes across 21 cases covering all 19 revision-274 skills.
It saves screenshots during actions and verifies changing sequence frames and
mesh bounds, separately from server XP/item assertions. Fixtures are fresh QA
accounts; the browser character is not edited. Original actions without an
animation (identifying herbs and feathering shafts) remain without one; animated
potion mixing and log fletching are also exercised.
The first run is preserved in `Saved/skill-animations-20260927`: HP and thieving
XP arrived before observation completed; Wind Strike selected an unreachable
man; the level-3 fishing character died to an aggressive NPC; and log balancing
uses a changed base gait rather than a primary action. The rerun gives visual
observation up to two additional seconds, casts east of Lumbridge after two blocked targets, supplies
fishing defence/HP as fixture prerequisites, and checks agility's original
non-default walk sequence. These are test changes, not bypasses of gameplay.
The targeted rerun passed hitpoints, fishing (net sequence 621, shrimp and XP),
agility (log-balance gait 762), and thieving (881, coins and XP). The separate
open-field magic run passed Wind Strike sequence 711 with twelve observed
frames, rune consumption and magic XP. Combined with the first pass, all 21
cases / 19 skills have successful normal-gameplay outcomes and required visual
assertions. Native woodcutting screenshots show the bronze axe in its chopping
pose, its removal after completion, and the repaired logs in inventory. This is
representative coverage per skill, not exhaustive testing of every recipe,
weapon tier, quest animation, gender or equipment combination.
The fresh native client-control regression also passed: original NPC death
sequence 836 reached its final pose, bones appeared and were picked up, and a
subsequent exact-tree action produced logs and Woodcutting XP while a scimitar
was equipped. Invalid/stale control targets were rejected as before.
The final feedback regression passed all 12 facing checks, both actors facing in
combat, six received hits, rendered health bars/hit splats, hover text, menus,
click feedback and original sprite transparency. The browser's native client
was confirmed connected and able to act after all fixture configurations were
removed.
