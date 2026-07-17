import os
import sqlite3
from datetime import datetime, timezone
from urllib.parse import urlparse, urlunparse

import httpx

TA_API_URL = lambda: os.environ.get("TA_API_URL", "http://tubearchivist:8000")
TA_API_KEY = lambda: os.environ.get("TA_API_KEY", "")
METUBE_API_URL = lambda: os.environ.get("METUBE_API_URL", "http://metube:8081")


def detect_platform(url):
    hostname = urlparse(url).hostname or ""
    if "youtube.com" in hostname or "youtu.be" in hostname:
        return "youtube"
    if "soundcloud.com" in hostname:
        return "soundcloud"
    if "twitch.tv" in hostname:
        return "twitch"
    return "other"


def strip_query(url):
    try:
        parsed = urlparse(url)
        return urlunparse(parsed._replace(query="", fragment=""))
    except Exception:
        return url


def normalize_metube_item(item):
    url = strip_query(item.get("url", ""))
    platform = detect_platform(url)
    filename = item.get("filename", "")
    is_audio = platform == "soundcloud" or filename.endswith(
        (".mp3", ".m4a", ".ogg", ".opus", ".flac")
    )
    return {
        "id": f"mt_{item['id']}",
        "source": "metube",
        "media_type": "audio" if is_audio else "video",
        "title": item.get("title", ""),
        "url": url,
        "platform": platform,
        "channel": "",
        "thumbnail_path": "",
        "file_path": f"/data/media/{filename}" if filename else "",
        "audio_path": f"/data/media/{filename}" if is_audio and filename else "",
        "duration": None,
        "file_size": item.get("size"),
        "tags": "",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


def normalize_ta_item(item):
    channel = item.get("channel", {})
    duration_str = item.get("player", {}).get("duration_str", "0:00")
    parts = duration_str.split(":")
    try:
        if len(parts) == 3:
            duration = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
        elif len(parts) == 2:
            duration = int(parts[0]) * 60 + int(parts[1])
        else:
            duration = 0
    except ValueError:
        duration = 0

    return {
        "id": f"ta_{item['youtube_id']}",
        "source": "tubearchivist",
        "media_type": "video",
        "title": item.get("title", ""),
        "url": f"https://www.youtube.com/watch?v={item['youtube_id']}",
        "platform": "youtube",
        "channel": channel.get("channel_name", "") if isinstance(channel, dict) else "",
        "thumbnail_path": item.get("vid_thumb_url", ""),
        "file_path": item.get("media_url", ""),
        "audio_path": "",
        "duration": duration,
        "file_size": None,
        "tags": "",
        "created_at": item.get("published", datetime.now(timezone.utc).isoformat()),
    }


def sync_metube(db):
    try:
        resp = httpx.get(f"{METUBE_API_URL()}/history", timeout=10)
        resp.raise_for_status()
        history = resp.json()
    except Exception as e:
        print(f"[sync] MeTube fetch failed: {e}")
        return 0

    count = 0
    for item in history.get("done", []):
        normalized = normalize_metube_item(item)
        existing = db.execute(
            "SELECT id FROM media WHERE id = ?", (normalized["id"],)
        ).fetchone()
        if not existing:
            db.execute(
                "INSERT INTO media (id, source, media_type, title, url, platform, channel, "
                "thumbnail_path, file_path, audio_path, duration, file_size, tags, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                tuple(normalized.values()),
            )
            count += 1
    db.commit()
    return count


def sync_tubearchivist(db):
    api_key = TA_API_KEY()
    if not api_key:
        print("[sync] No TA_API_KEY set, skipping TubeArchivist sync")
        return 0

    try:
        resp = httpx.get(
            f"{TA_API_URL()}/api/video/",
            headers={"Authorization": f"Token {api_key}"},
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        print(f"[sync] TubeArchivist fetch failed: {e}")
        return 0

    count = 0
    videos = data.get("data", [])
    for item in videos:
        normalized = normalize_ta_item(item)
        existing = db.execute(
            "SELECT id FROM media WHERE id = ?", (normalized["id"],)
        ).fetchone()
        if not existing:
            db.execute(
                "INSERT INTO media (id, source, media_type, title, url, platform, channel, "
                "thumbnail_path, file_path, audio_path, duration, file_size, tags, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                tuple(normalized.values()),
            )
            count += 1
    db.commit()
    return count


def apply_channel_rules(db):
    rules = db.execute(
        "SELECT channel, mode FROM channel_rules WHERE mode = 'audio_only'"
    ).fetchall()
    for rule in rules:
        db.execute(
            "UPDATE media SET media_type = 'audio' WHERE channel = ? AND media_type = 'video' AND audio_path = ''",
            (rule["channel"],),
        )
    db.commit()


def run_sync(db):
    mt_count = sync_metube(db)
    ta_count = sync_tubearchivist(db)
    apply_channel_rules(db)
    print(f"[sync] Added {mt_count} from MeTube, {ta_count} from TubeArchivist")
    return mt_count + ta_count
