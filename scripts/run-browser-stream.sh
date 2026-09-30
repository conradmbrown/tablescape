#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
APP="$ROOT/runtime/selkies-2.0.0/squashfs-root"
export DISPLAY=:98
export XDG_RUNTIME_DIR="/run/user/$(id -u)/scape-browser"
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"
export PULSE_SERVER="unix:$PULSE_RUNTIME_PATH/native"
export PULSE_SINK=scape PULSE_SOURCE=scape.monitor
export XDG_CONFIG_HOME="$XDG_RUNTIME_DIR/config"
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
mkdir -p "$PULSE_RUNTIME_PATH" "$XDG_CONFIG_HOME" "$ROOT/Saved/browser-stream"
chmod 700 "$XDG_RUNTIME_DIR" "$PULSE_RUNTIME_PATH"
if [[ -S /tmp/.X11-unix/X98 ]]; then
  echo 'Display :98 is already in use; refusing to attach to another session.' >&2
  exit 1
fi
children=()
unity_started=false
cleanup(){
  trap - EXIT TERM INT
  for child in "${children[@]}"; do kill "$child" 2>/dev/null || true; done
  wait || true
  if $unity_started; then date +%s > "$ROOT/Saved/browser-stream/last-stop"; fi
}
trap cleanup EXIT TERM INT
Xvfb "$DISPLAY" -screen 0 1440x900x24 -s 0 -dpms +extension GLX +extension XTEST +extension MIT-SHM -nolisten tcp -ac -noreset > "$ROOT/Saved/browser-stream/display.log" 2>&1 &
children+=("$!")
for attempt in {1..100}; do [[ -S /tmp/.X11-unix/X98 ]] && break; sleep .1; done
[[ -S /tmp/.X11-unix/X98 ]]
cat > "$XDG_CONFIG_HOME/pulse.pa" <<PULSE
load-module module-native-protocol-unix socket=$PULSE_RUNTIME_PATH/native auth-anonymous=1
load-module module-null-sink sink_name=scape channels=2 rate=48000
set-default-sink scape
set-default-source scape.monitor
PULSE
"$APP/usr/conda/bin/pulseaudio" -n --daemonize=no --disallow-exit --exit-idle-time=-1 --disable-shm=true -p "$APP/usr/conda/lib/pulseaudio/modules" -F "$XDG_CONFIG_HOME/pulse.pa" > "$ROOT/Saved/browser-stream/audio.log" 2>&1 &
children+=("$!")
for attempt in {1..100}; do [[ -S "$PULSE_RUNTIME_PATH/native" ]] && break; sleep .1; done
[[ -S "$PULSE_RUNTIME_PATH/native" ]]
# The gateway expires a disconnected transport after 60 seconds, checked every 5s.
# Wait only after a previous stream shutdown, preserving inventory and the save.
if [[ -f "$ROOT/Saved/browser-stream/last-stop" ]]; then
  last_stop="$(cat "$ROOT/Saved/browser-stream/last-stop")"
  if [[ "$last_stop" =~ ^[0-9]+$ ]]; then
    remaining=$((67 - $(date +%s) + last_stop))
    if (( remaining > 0 && remaining <= 67 )); then
      echo "Waiting $remaining seconds for the previous game session to close."
      sleep "$remaining"
    fi
  fi
fi
umask 077
mkdir -p "$ROOT/Saved/client-control"
chmod 700 "$ROOT/Saved/client-control"
unity_started=true
"$ROOT/Builds/Linux/ScapeClient" --scape-control-dir="$ROOT/Saved/client-control" -force-vulkan -popupwindow -screen-fullscreen 0 -screen-width 1440 -screen-height 900 -logFile "$ROOT/Saved/browser-stream/unity.log" &
children+=("$!")
python3 "$ROOT/scripts/focus-stream-window.py"
"$APP/AppRun" --addr=127.0.0.1 --port=8891 --enable-https=false --enable-basic-auth=false --encoder=h264enc --framerate=30 --video-bitrate=8000 --enable-resize=false --manual-resolution=true --manual-width=1440 --manual-height=900 --audio-device-name=scape.monitor --enable-clipboard=false --file-transfers=none --microphone-enabled=false --webcam-enabled=false --gamepad-enabled=false --printing-enabled=false --ui-title="Lost City browser test" --ui-show-logo=false > "$ROOT/Saved/browser-stream/selkies.log" 2>&1 &
children+=("$!")
wait -n "${children[@]}"
echo "A stream component exited; restarting the session." >&2
exit 1
