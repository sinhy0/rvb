#!/bin/bash
set -euo pipefail

cd build || { echo "build folder not found"; exit 1; }

: "${TG_TOKEN:?TELEGRAM_BOT_TOKEN is not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID is not set}"
: "${NEXT_VER_CODE:?NEXT_VER_CODE is not set}"
: "${GITHUB_SERVER_URL:?GITHUB_SERVER_URL is not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

NL=$'\n'
RELEASE_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/releases/tag/${NEXT_VER_CODE}"
BUILD_INFO="../build.tmp"

if [ ! -f "$BUILD_INFO" ]; then
  echo "build.tmp not found"
  exit 1
fi

declare -a APPS=()
APP_RE='^(.+) \(([^)]*)\): (.+)$'
while IFS= read -r line; do
  if [[ "$line" =~ $APP_RE ]]; then
    app="${BASH_REMATCH[1]}"
    version="${BASH_REMATCH[3]}"
    if [[ "$version" =~ ^[0-9]+([.][0-9A-Za-z-]+)*$ ]]; then
      pair="${app}"$'\t'"${version}"
      duplicate=false
      for existing in "${APPS[@]:-}"; do
        [ "$existing" = "$pair" ] && duplicate=true && break
      done
      [ "$duplicate" = false ] && APPS+=("$pair")
    fi
  fi
done < "$BUILD_INFO"

if [ "${#APPS[@]}" -eq 0 ]; then
  APPS+=("Build"$'\t'"${NEXT_VER_CODE}")
fi

# Use the versions recorded by the build itself.
PATCH_VERSION="$(sed -n 's/^Patches:[[:space:]].*patches-\([^/[:space:]]*\)\.mpp.*$/\1/p' "$BUILD_INFO" | head -n 1)"
MORPHE_DESKTOP_VERSION="$(sed -n 's;^CLI:[[:space:]].*morphe-desktop-\([^/[:space:]]*\)-all\.jar.*$;\1;p' "$BUILD_INFO" | head -n 1)"

escape_html() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

send_message() {
  local text="$1"
  local response
  response="$(curl -fsS -X POST \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=false" \
    --data-urlencode "text=${text}" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage")"
  echo "$response" | grep -q '"ok":true' || {
    echo "Telegram API error: $response" >&2
    return 1
  }
}

# Send one message per application. The link opens the corresponding GitHub Release,
# where the APK assets can be downloaded.
for pair in "${APPS[@]}"; do
  app="${pair%%$'\t'*}"
  version="${pair#*$'\t'}"

  app_esc="$(printf '%s' "$app" | escape_html)"
  version_esc="$(printf '%s' "$version" | escape_html)"
  patch_esc="$(printf '%s' "${PATCH_VERSION:-unknown}" | escape_html)"
  morphe_esc="$(printf '%s' "${MORPHE_DESKTOP_VERSION:-unknown}" | escape_html)"

  MSG="🎉 New Builds Available${NL}${NL}"
  MSG+="${app_esc} ${version_esc}${NL}"
  MSG+="Patches: ${patch_esc}${NL}"
  MSG+="Morphe Desktop: ${morphe_esc}${NL}${NL}"
  MSG+="📥 Download:${NL}"
  MSG+="<a href=\"${RELEASE_URL}\">${RELEASE_URL}</a>"

  send_message "$MSG"
done
