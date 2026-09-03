#!/bin/bash
set -euo pipefail

cd build || { echo "build folder not found"; exit 1; }

: "${TG_TOKEN:?TG_TOKEN is not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID is not set}"
: "${NEXT_VER_CODE:?NEXT_VER_CODE is not set}"
: "${GITHUB_SERVER_URL:?GITHUB_SERVER_URL is not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

# build.tmp contains the build summary generated before the Release is created.
BUILD_LOG="../build.tmp"

# Extract the patch version and Morphe Desktop version from the build summary.
PATCH_VERSION="$(grep -Eo 'Patches:[[:space:]]*[0-9A-Za-z._-]+' "$BUILD_LOG" 2>/dev/null | head -n1 | sed -E 's/^Patches:[[:space:]]*//' || true)"

MORPHE_DESKTOP_VERSION="$(grep -Eo 'morphe-desktop-[0-9A-Za-z._-]+' "$BUILD_LOG" 2>/dev/null | head -n1 | sed 's/^morphe-desktop-//' || true)"

# Fallback if the summary already contains the friendly label.
if [ -z "$MORPHE_DESKTOP_VERSION" ]; then
  MORPHE_DESKTOP_VERSION="$(grep -Eo 'Morphe Desktop:[[:space:]]*[0-9A-Za-z._-]+' "$BUILD_LOG" 2>/dev/null | head -n1 | sed -E 's/^Morphe Desktop:[[:space:]]*//' || true)"
fi

PATCH_VERSION="${PATCH_VERSION:-unknown}"
MORPHE_DESKTOP_VERSION="${MORPHE_DESKTOP_VERSION:-unknown}"

# Convert an APK filename into the requested display name and app version.
get_app_name() {
  local filename="$1"
  local base="${filename%.apk}"
  local prefix="${base%%-v*}"

  case "$prefix" in
    youtube-music-morphe) echo "YouTube Music" ;;
    youtube-morphe)       echo "YouTube" ;;
    instagram-piko)      echo "Instagram" ;;
    twitter-piko)        echo "Twitter" ;;
    tiktok-piko)         echo "TikTok" ;;
    reddit-piko)         echo "Reddit" ;;
    spotify-morphe)      echo "Spotify" ;;
    *)                   echo "$prefix" | sed -E 's/-(morphe|piko)$//' | sed 's/-/ /g; s/\b\(.\)/\u\1/g' ;;
  esac
}

get_app_version() {
  local filename="$1"
  local base="${filename%.apk}"
  local after_v="${base#*-v}"

  # Remove the architecture/build suffix after the version.
  after_v="${after_v%-all}"
  after_v="${after_v%-arm64-v8a}"
  after_v="${after_v%-universal}"

  echo "$after_v"
}

# Build the direct GitHub Release asset URL. This points to the .apk itself,
# not the Release page.
for APK in *.apk; do
  [ -f "$APK" ] || continue

  APP_NAME="$(get_app_name "$APK")"
  APP_VERSION="$(get_app_version "$APK")"
  DOWNLOAD_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/releases/download/${NEXT_VER_CODE}/${APK}"

  MESSAGE="🎉 New Build Available

${APP_NAME} ${APP_VERSION}
Patches: ${PATCH_VERSION}
Morphe Desktop: ${MORPHE_DESKTOP_VERSION}

📥 Download:
${DOWNLOAD_URL}"

  curl --fail --silent --show-error --request POST \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${MESSAGE}" \
    --data-urlencode "disable_web_page_preview=true" \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" >/dev/null

  echo "Telegram notification sent for: ${APK}"
done
