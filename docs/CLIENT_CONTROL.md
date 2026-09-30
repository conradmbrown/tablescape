> Configure `SCAPE_SSH_HOST` with your SSH alias and `SCAPE_REMOTE_SOURCE` with the absolute remote checkout path before using `scripts/remote-client.command`. No machine identity is supplied by this repository.

# Native Unity client control

The browser-stream Unity process enables a private local command directory at `Saved/client-control` on the game server. Commands are consumed on Unity's main thread and invoke the same action queue, targeting and widget handlers as the client UI. This controls the **existing browser character**; it does not create a second session or impersonate the client through the backend.

From the Mac checkout:

```sh
scripts/remote-client.command nearby --operation Chop-down
scripts/remote-client.command chop 'EXACT_KEY_FROM_NEARBY'
scripts/remote-client.command nearby --name Hans
scripts/remote-client.command act 'EXACT_NPC_KEY' Talk-to
scripts/remote-client.command state
scripts/remote-client.command button 4886
scripts/remote-client.command action '{"kind":"move","x":3222,"z":3218}'
scripts/remote-client.command camera 25 55 22
scripts/remote-client.command capture
```

Use an actual widget ID from the current state's `ui`, rather than assuming the example Continue ID applies to every dialogue. Targets have explicit stable keys and advertised operations; actions against missing targets or unsupported operations are rejected. Hyphens/spaces in operation names are normalized. `nearby` defaults to 16 tiles; `--radius`, `--name`, and `--operation` filter its output. Full state includes rendered targets, visibility, animation sequence/frame, player/inventory/XP, dialogue widgets, and world entities.

On the game server, use `python3 scripts/client-control.py` with the same arguments. `--directory` selects a separately launched QA client's control directory. The read-only `state` command remains available while disconnected. Gameplay commands require a connected client; the current `state.busy` flag reports server action delays.

The running Unity process must opt in with `--scape-control-dir=...`; the browser launcher does so automatically. Standalone tests use isolated directories and fresh characters.

A response saying `queued` only confirms native dispatch. Read state afterward to verify a server outcome such as logs entering inventory, Woodcutting XP increasing, a dialogue opening, or an NPC dropping bones. Game rules, skill requirements, distances, action delays, and inventory constraints still apply. This interface grants no staff privileges and does not implement game features that the Unity client still lacks.

The directory is owner-only, uses atomic request/response files, binds each command to the current Unity process ID and rejects requests older than 15 seconds. It opens no network port; access from the Mac uses the existing game server SSH connection. Commands are never automatically retried after a timeout, because the action might already have executed. `capture` queues a native rendered-frame PNG and returns its server path; wait for the file before reading it. `logout` affects the browser character.
