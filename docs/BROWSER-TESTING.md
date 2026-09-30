# Stream the native Unity client

The optional browser surface streams a native Unity process; it is not the original web game client or the native visionOS app.

On your Linux game server, install the stream's dependencies and configure the `service/units/scape-browser-stream.service` template with your checkout path and environment. The launcher expects that user service and a private loopback listener on port 8891. See `scripts/run-browser-stream.sh` for its runtime dependencies; this is not a fresh-machine installer.

On the Mac, configure and verify an SSH alias using your own account/key and known-host entry, then run:

```sh
export SCAPE_SSH_HOST='your-configured-ssh-alias'
bash scripts/open-browser-test.command
```

The launcher starts the remote stream service, waits for health, forwards server loopback port 8891 to Mac loopback port 8891, and opens the local page. It stops the standalone Unity client service first to avoid competing interactive clients. `SCAPE_PORT` can select a different local port, and `SCAPE_NO_OPEN=1` skips opening the browser. Authentication comes from SSH configuration; there is no embedded account, key path or server address.

To close the tunnel:

```sh
ssh -S "${TMPDIR:-/tmp}/scape-browser-${UID}.sock" -O exit "$SCAPE_SSH_HOST"
```

Check the configured service's journal and local `Saved/browser-stream/` logs when diagnosing startup. Do not publish runtime logs, credentials or personal desktop captures.
