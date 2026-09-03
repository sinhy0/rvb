#!/usr/bin/env python3
import asyncio
import glob
import json
import os
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen

from telethon import TelegramClient
from telethon.sessions import StringSession

BOT_TOKEN = os.environ["TG_TOKEN"]
API_ID = int(os.environ["TELEGRAM_API_ID"])
API_HASH = os.environ["TELEGRAM_API_HASH"]
CHANNEL_ID = int(os.environ.get("TG_CHAT_ID", "-1001864511857"))
TAG = os.environ["NEXT_VER_CODE"]
REPO = os.environ["GITHUB_REPOSITORY"]
SERVER = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
GH_TOKEN = os.environ.get("GITHUB_TOKEN", "")

UPLOAD_CONNECTIONS = 4

APP_NAMES = {
    "instagram": "Instagram",
    "twitter": "Twitter",
    "x": "Twitter",
    "youtube": "YouTube",
    "youtube-music": "YouTube Music",
    "youtube_music": "YouTube Music",
    "tiktok": "TikTok",
    "reddit": "Reddit",
}


def log(msg):
    print(msg, flush=True)


def get_release():
    url = f"{SERVER}/api/v3/repos/{REPO}/releases/tags/{TAG}" if SERVER != "https://github.com" else f"https://api.github.com/repos/{REPO}/releases/tags/{TAG}"
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "RVB-GitHub-Action-Telegram"}
    if GH_TOKEN:
        headers["Authorization"] = f"Bearer {GH_TOKEN}"
    req = Request(url, headers=headers)
    with urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def apk_data(filename):
    stem = re.sub(r"\.apk$", "", filename, flags=re.I)
    m = re.search(r"-v(.+?)-all$", stem, flags=re.I)
    if not m:
        m = re.search(r"-v(.+)$", stem, flags=re.I)
    version = m.group(1) if m else ""
    slug = stem[:m.start()] if m else stem
    slug = re.sub(r"-(morphe-piko|morphe|piko)$", "", slug, flags=re.I).lower()
    return APP_NAMES.get(slug, slug.replace("-", " ").title()), version, slug


def patch_data(slug, release):
    # Prefer the release's generated patch entries so future patch versions
    # are picked up automatically. Fall back to the known app/repository map.
    text = "\n".join(str(release.get(k, "")) for k in ("name", "body", "html_url"))
    candidates = re.findall(r"(?i)(crimera|MorpheApp)[^\n]*?patches-([0-9]+(?:\.[0-9]+){1,3})\.mpp", text)
    if slug in {"instagram", "twitter", "x", "tiktok", "reddit"}:
        for owner, ver in candidates:
            if owner.lower() == "crimera":
                return "piko", ver
        return "piko", "3.9.0"
    if slug in {"youtube", "youtube-music", "youtube_music"}:
        for owner, ver in candidates:
            if owner.lower() == "morpheapp":
                return "morphe-patches", ver
        return "morphe-patches", "1.41.0"
    return "", ""


def desktop_version(release):
    assets = release.get("assets", [])
    text = "\n".join([
        str(release.get("name", "")),
        str(release.get("body", "")),
        str(release.get("html_url", "")),
        *[str(a.get("name", "")) for a in assets],
    ])
    patterns = [
        r"morphe-desktop-([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)(?:-all)?\.jar",
        r"morphe-desktop-([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)",
    ]
    for pattern in patterns:
        m = re.search(pattern, text, re.I)
        if m:
            return m.group(1)
    return ""


def caption(app, version, patch, patch_version, desktop):
    lines = ["🎉 New Build Available", "", f"{app} {version}"]
    if patch:
        lines.append(f"Patches: {patch} {patch_version}")
    if desktop:
        lines.append(f"Morphe Desktop: {desktop}")
    return "\n".join(lines)


async def upload_one(client, path, text, index, total):
    log(f"⬆️ Uploading {index}/{total}: {Path(path).name}")
    await client.send_file(
        CHANNEL_ID,
        path,
        force_document=True,
        caption=text,
        part_size_kb=512,
    )
    log(f"✓ Uploaded {index}/{total}: {Path(path).name}")


async def main(items):
    clients = []
    try:
        # Independent MTProto sessions/connections. This lets different APKs
        # upload concurrently instead of waiting for each other.
        for i in range(UPLOAD_CONNECTIONS):
            client = TelegramClient(
                StringSession(),
                API_ID,
                API_HASH,
                connection_retries=10,
                retry_delay=2,
                request_retries=5,
                auto_reconnect=True,
            )
            await client.start(bot_token=BOT_TOKEN)
            clients.append(client)

        async def worker(index, item):
            path, text = item
            client = clients[index % len(clients)]
            await upload_one(client, path, text, index + 1, len(items))

        await asyncio.gather(*(worker(i, item) for i, item in enumerate(items)))
    finally:
        await asyncio.gather(*(c.disconnect() for c in clients), return_exceptions=True)


def main_sync():
    build_dir = Path("build")
    apk_paths = sorted(glob.glob(str(build_dir / "*.apk")))
    if not apk_paths:
        raise RuntimeError("No APK files found in build/")

    log(f"Found {len(apk_paths)} APK files.")
    release = get_release()
    desktop = desktop_version(release)
    if desktop:
        log(f"Morphe Desktop: {desktop}")
    else:
        log("Warning: Morphe Desktop version was not found in the release metadata.")

    items = []
    for path in apk_paths:
        app, version, slug = apk_data(Path(path).name)
        patch, patch_version = patch_data(slug, release)
        text = caption(app, version, patch, patch_version, desktop)
        log("---")
        log(text)
        items.append((path, text))

    asyncio.run(main(items))
    log(f"Telegram upload completed: {len(items)} APK(s).")


if __name__ == "__main__":
    try:
        main_sync()
    except Exception as exc:
        print(f"::error::Telegram upload failed: {exc}", file=sys.stderr, flush=True)
        raise
