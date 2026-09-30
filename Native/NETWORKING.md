# Native networking and the private headset bridge

TableScape connects to the existing Lost City gateway. The Simulator can use a Mac loopback SSH tunnel; a physical Vision Pro needs a reachable private HTTPS address. Build and install the native app first using [README.md](README.md). The paths below keep source, runtime material and build output on the external SSD; substitute your checkout/private directory and current network identity where appropriate.

## Simulator: reuse the SSH tunnel

```text
visionOS Simulator → http://127.0.0.1:18890 on the Mac
                   → authenticated SSH to game server
                   → http://127.0.0.1:8890 on game server
```

The established forwarding configuration is `-L 127.0.0.1:18890:127.0.0.1:8890`. Reuse an existing tunnel. If it is absent, run the following in a separate terminal; `SCAPE_SSH_HOST` must name your configured SSH host alias, not a public gateway address:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes \
  -o ExitOnForwardFailure=yes -N \
  -L 127.0.0.1:18890:127.0.0.1:8890 "$SCAPE_SSH_HOST"
```

The gateway must already be running on game server loopback. On a Simulator, set **Game server** to `http://127.0.0.1:18890`, enter a development character name and connect. This direct connection does not need a bridge key or LAN listener. If you use another gateway host or port, update the forward and endpoint together.

## Vision Pro: start the private HTTPS bridge

```text
Vision Pro → HTTPS private Mac address, port 8443
           → bridge key authentication
           → Mac loopback SSH tunnel, port 18890
           → game server loopback gateway, port 8890
```

Keep the tunnel and Mac awake. Choose a Mac private address reachable from the headset on the intended LAN or tailnet; same-LAN Wi-Fi does not require Tailscale on the headset. Read the current address from the appropriate network interface, for example `ipconfig getifaddr en0`; do not reuse an old receipt's IP address without checking it.

Set `SCAPE_WORKSPACE` as described in the native setup guide, then provision a TLS server certificate and matching private key through your supported private CA. Its Subject Alternative Name must match the IP address or private DNS name the app will use. Keep private keys and deployment files outside source and public artifacts, such as `$SCAPE_WORKSPACE/Private`, with owner-only permissions. Generate a 256-bit bridge key using a cryptographically secure generator and retain it in the supported password manager or Keychain. The required representation is 64 hexadecimal characters; never put the key in a URL or command history.

From the SSD checkout, this zsh example prompts for the current literal private bind IP and reads the existing bridge key without echoing it:

```sh
read -r 'SCAPE_BRIDGE_BIND?Mac private bind IP: '
read -r -s 'SCAPE_BRIDGE_KEY?Bridge key: '
export SCAPE_BRIDGE_KEY
PYTHONDONTWRITEBYTECODE=1 python3 scripts/native-private-bridge.py \
  --bind "$SCAPE_BRIDGE_BIND" --port 8443 \
  --upstream http://127.0.0.1:18890 \
  --certificate "$SCAPE_WORKSPACE/Private/bridge-server.crt" \
  --private-key "$SCAPE_WORKSPACE/Private/bridge-server.key"
unset SCAPE_BRIDGE_KEY SCAPE_BRIDGE_BIND
```

Replace the certificate paths with your provisioned files. This foreground process stops with Control-C. It does not install launch agents, modify firewalls, publish DNS or configure routers. The chosen address and port must already be reachable under the intended private-network policy. Configure the app using one of the two trust options below.

### Option A: system-trusted CA and manual app setup

Use the organization's supported device trust process so Vision Pro trusts the server certificate's CA. In TableScape, disconnect before changing settings, enter the certificate-matching HTTPS origin in **Game server**, open **Private connection**, enter the same bridge key and select **Save key**. Then enter the character name and connect.

The key is saved in device-only Keychain storage for the exact normalized endpoint. Ordinary Apple certificate validation applies unless an app-specific CA was previously imported for that same origin. The bridge still binds a literal private IP even when the app uses a private DNS name. Do not disable certificate validation.

### Option B: one-use app-scoped CA import

For a paired developer device, `NativeBridgeDeployment` in [Core/BridgeCredential.swift](TableScape/Core/BridgeCredential.swift) supports copying a private setup file into the installed app's data container. This installs trust only inside TableScape for one HTTPS origin; it does not install a system-wide CA or trust exception.

Create an owner-readable-only `PrivateConnection.json` outside the checkout. It is a JSON object with string values and these required fields:

| Field | Value and validation |
| --- | --- |
| `endpoint` | HTTPS origin with a literal RFC1918 IPv4 address: `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`. An optional port and trailing `/` are supported; credentials, other paths, queries and fragments are rejected. |
| `bridgeKey` | The actual bridge key, exactly 64 hexadecimal characters. It must match the bridge process; the bridge also rejects obviously repetitive values. |
| `certificateAuthority` | Base64 of the CA certificate's DER bytes, not PEM text and never a private key. The decoded certificate must be valid certificate data and at most 16,384 bytes. |

The whole JSON file must be nonempty and at most 32,768 bytes. This importer does **not** accept DNS names, IPv6 or tailnet `100.64.0.0/10` addresses; use system trust and manual setup for those identities. The bridge itself supports those private bind ranges.

With the development app installed and the headset paired, connected and unlocked, choose its identifier from `xcrun devicectl list devices`. These command forms were checked against the installed `devicectl` help:

```sh
read -r 'SCAPE_DEVICE?Paired Vision Pro identifier: '
xcrun devicectl device copy to --device "$SCAPE_DEVICE" \
  --source "$SCAPE_WORKSPACE/Private/PrivateConnection.json" \
  --destination Documents/PrivateConnection.json \
  --domain-type appDataContainer \
  --domain-identifier com.innoiso.tablescape.native
xcrun devicectl device process launch --device "$SCAPE_DEVICE" \
  --terminate-existing com.innoiso.tablescape.native
unset SCAPE_DEVICE
```

Launching a fresh process triggers import during `GameSession` initialization. It saves the bridge key in Keychain, stores the CA in app preferences under the normalized endpoint, selects that endpoint and deletes the device setup file after successful import. The local source file is not deleted automatically; remove that one-use copy after confirming successful import, retaining the authoritative key/CA in their secure locations. Invalid input is not consumed and logs only `TABLESCAPE_CONNECTION_IMPORT_FAILED`; correct the private file and restart the app.

For the imported host and port, the transport evaluates the chain against that CA and retains certificate validity, server-auth usage and actual IP SAN checks. Other origins use default system trust. A changed IP or port needs the corresponding certificate identity and endpoint configuration. **Remove saved key** removes the endpoint's bridge credential; it does not remove its imported CA preference.

## Connection verification and troubleshooting

Use a separate development character to verify login, continuing state updates, loaded assets and a movement action from the actual headset. A successful build, file copy or `/health` response alone does not establish this. If the server cannot be reached, check the Mac's current address, private-network reachability, running bridge and loopback tunnel. For TLS failures, check the certificate's SAN, validity and the selected system/app CA path. A locked or disconnected developer device can block copy or launch independently of game networking.

For local bridge-only checks, omit bind/certificate/private-key arguments and use `http://127.0.0.1:18891`; `SCAPE_BRIDGE_KEY` is still required. This does not test headset reachability or TLS trust.

## Authentication and transport boundaries

- Every bridge request, including `/health` and assets, requires `X-TableScape-Bridge-Key`, compared using `hmac.compare_digest`. This is separate from the game's `Authorization: Bearer …` token; the bridge strips its own key and forwards only the game bearer. Native client and bridge both refuse redirects.
- The default listener is `127.0.0.1:18891`. Nonloopback private LAN, tailnet or IPv6 ULA binds require both TLS certificate and private key; wildcard, public and hostname binds are rejected. There is no external-TLS-termination bypass.
- Upstream must be a literal loopback HTTP(S) origin without credentials, other paths, queries or fragments. HTTPS upstreams use normal Python certificate validation. The bridge cannot proxy arbitrary destinations.
- Browser `Origin` requests, arbitrary routes, duplicate sensitive/framing headers, chunked bodies and body-bearing GET/DELETE requests are rejected. Allowed routes match the gateway's session/action, state/terrain/chunk, models/textures/sequences, overlays and sound/music contract.
- Action/session JSON is limited to 2,048 bytes. Other upstream responses are limited to 16,000,000 bytes and audio to 64,000,000 bytes. Responses are bounded in memory and not cached to disk. Four active connections are allowed by default; `--max-connections` accepts 1–8. Four maximum audio responses can occupy about 256 MB plus runtime overhead. Request/header timeouts and separate 15/65-second upstream timeouts bound stalled connections.
- Each request has one upstream attempt. A lost action response returns `GATEWAY_UNCERTAIN`; the bridge never retries the action. Preserve the native client's uncertain-action recovery behavior.
- Request paths/bodies, bridge keys and bearer tokens are not logged. Startup logs only listener address and mode. Unknown or oversized responses are rejected; caller-controlled forwarding headers and cookies are not relayed.

## Reproducible isolated bridge tests

From the source checkout:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-native-private-bridge.py
```

These tests use ephemeral loopback listeners and a mock gateway. They cover bind/TLS rules, route restrictions, authentication, separate bearer forwarding, browser/framing rejection, request/response limits, truncated responses, redirects, secret-free logs, verified loopback TLS and exactly one upstream mutation attempt after failure. They never contact the live game gateway. Temporary TLS material is created under `Build/BridgeTests` on configured storage and removed by the test; no downloaded packages are required.

## Verification scope

A recorded device run established a private TLS connection, game-state updates and asset loading. It does not establish current server availability, physical tracking, all gameplay, comfort or headset performance. Deployment receipts and private restart/renewal notes are deliberately not part of this repository. Validate your own endpoint and runtime after setup.
