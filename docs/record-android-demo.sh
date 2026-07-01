#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXAMPLE_DIR="${EXAMPLE_DIR:-../react-native-client-example}"
APK_PATH="$EXAMPLE_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="${APP_ID:-com.example}"
ACTIVITY="${ACTIVITY:-.MainActivity}"
RECORD_SECONDS="${RECORD_SECONDS:-40}"
GIF_INPUT_SECONDS="${GIF_INPUT_SECONDS:-40}"
GIF_SPEED="${GIF_SPEED:-2.5}"
START_METRO="${START_METRO:-1}"
INSTALL_APK="${INSTALL_APK:-1}"
TAP_Y_PERCENT="${TAP_Y_PERCENT:-31}"
PRE_TAP_SECONDS="${PRE_TAP_SECONDS:-2}"
RUN_BEFORE_HOME_SECONDS="${RUN_BEFORE_HOME_SECONDS:-6}"
HOME_SECONDS="${HOME_SECONDS:-5}"
RUN_BEFORE_FORCE_STOP_SECONDS="${RUN_BEFORE_FORCE_STOP_SECONDS:-6}"
FORCE_CLOSED_SECONDS="${FORCE_CLOSED_SECONDS:-2}"
RESUME_AFTER_RELAUNCH_SECONDS="${RESUME_AFTER_RELAUNCH_SECONDS:-10}"
REMOTE_VIDEO="/sdcard/react-native-client-demo.mp4"
LOCAL_VIDEO="docs/demo.mp4"
LOCAL_GIF="docs/demo.gif"
METRO_LOG="docs/metro-recording.log"
METRO_PID=""

cleanup() {
  if [ -n "$METRO_PID" ] && kill -0 "$METRO_PID" >/dev/null 2>&1; then
    kill "$METRO_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required" >&2
  exit 1
fi

if ! adb get-state >/dev/null 2>&1; then
  echo "No Android device or emulator is available through adb" >&2
  exit 1
fi

if [ ! -f "$APK_PATH" ]; then
  echo "Debug APK not found. Building example app..."
  (cd "$EXAMPLE_DIR/android" && ./gradlew :app:assembleDebug)
fi

mkdir -p docs

if [ "$START_METRO" = "1" ]; then
  echo "Starting Metro for the example app..."
  if command -v bun >/dev/null 2>&1; then
    (cd "$EXAMPLE_DIR" && bun run start -- --host 0.0.0.0 > "$ROOT_DIR/$METRO_LOG" 2>&1) &
  else
    (cd "$EXAMPLE_DIR" && npm run start -- --host 0.0.0.0 > "$ROOT_DIR/$METRO_LOG" 2>&1) &
  fi
  METRO_PID=$!
  sleep 8
fi

adb reverse tcp:8081 tcp:8081 || true
if [ "$INSTALL_APK" = "1" ]; then
  adb install -r "$APK_PATH"
fi
adb shell rm -f "$REMOTE_VIDEO"
adb shell am force-stop "$APP_ID" || true
adb shell run-as "$APP_ID" rm -f files/resume_demo.bin || true
adb shell am start -n "$APP_ID/$ACTIVITY"
sleep 6

SIZE="$(adb shell wm size | tr -d '\r' | awk -F': ' '/Physical size/ { print $2 }')"
WIDTH="${SIZE%x*}"
HEIGHT="${SIZE#*x}"
TAP_X=$((WIDTH / 2))
TAP_Y=$((HEIGHT * TAP_Y_PERCENT / 100))

adb shell screenrecord --bit-rate 6000000 --time-limit "$RECORD_SECONDS" "$REMOTE_VIDEO" &
RECORD_PID=$!

sleep "$PRE_TAP_SECONDS"
adb shell input tap "$TAP_X" "$TAP_Y"
sleep "$RUN_BEFORE_HOME_SECONDS"
adb shell input keyevent KEYCODE_HOME
sleep "$HOME_SECONDS"
adb shell am start -n "$APP_ID/$ACTIVITY"
sleep "$RUN_BEFORE_FORCE_STOP_SECONDS"
adb shell am force-stop "$APP_ID" || true
sleep "$FORCE_CLOSED_SECONDS"
adb shell am start -n "$APP_ID/$ACTIVITY"
sleep "$RESUME_AFTER_RELAUNCH_SECONDS"
wait "$RECORD_PID" || true

adb pull "$REMOTE_VIDEO" "$LOCAL_VIDEO"
ffmpeg -y -t "$GIF_INPUT_SECONDS" -i "$LOCAL_VIDEO" -vf "setpts=PTS/${GIF_SPEED},fps=10,scale=360:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" "$LOCAL_GIF"

echo "Wrote $LOCAL_VIDEO and $LOCAL_GIF"
