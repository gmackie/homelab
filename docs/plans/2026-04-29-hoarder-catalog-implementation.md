# Hoarder Catalog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand the image-api into a unified media catalog with tabbed UI, built-in playback, audio extraction, and channel rules.

**Architecture:** Extend existing FastAPI service with new SQLite tables, sync from TubeArchivist/MeTube APIs, serve HTML frontend, stream media files, and extract audio via ffmpeg.

**Tech Stack:** Python (FastAPI, SQLite, httpx), ffmpeg, HTML/CSS/JS

**Repo:** `/Volumes/dev/homelab` — all changes in `apps/internet-archive/image-api/`

---

## Task 1: Database Schema — Add media and channel_rules Tables

**Files:**
- Modify: `apps/internet-archive/image-api/main.py`
- Modify: `apps/internet-archive/image-api/test_main.py`

**Step 1: Write the failing test**

Add to `test_main.py`:

```python
@pytest.mark.anyio
async def test_catalog_empty(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
    resp = await client.get("/catalog?tab=video")
    assert resp.status_code == 200
    body = resp.json()
    assert body["items"] == []
    assert body["total"] == 0

@pytest.mark.anyio
async def test_channel_rules_empty(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
    resp = await client.get("/channels")
    assert resp.status_code == 200
    assert resp.json() == []
```

**Step 2: Run tests — expect FAIL**

Run: `cd apps/internet-archive/image-api && .venv/bin/pytest test_main.py -v`

**Step 3: Add tables to get_db() and stub endpoints**

Update `get_db()` in `main.py` to create the new tables:

```python
conn.execute(
    """CREATE TABLE IF NOT EXISTS media (
        id TEXT PRIMARY KEY,
        source TEXT NOT NULL,
        media_type TEXT NOT NULL,
        title TEXT,
        url TEXT,
        platform TEXT,
        channel TEXT,
        thumbnail_path TEXT,
        file_path TEXT,
        audio_path TEXT,
        duration INTEGER,
        file_size INTEGER,
        tags TEXT,
        created_at TEXT NOT NULL
    )"""
)
conn.execute(
    """CREATE TABLE IF NOT EXISTS channel_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel TEXT UNIQUE NOT NULL,
        platform TEXT,
        mode TEXT NOT NULL DEFAULT 'video'
    )"""
)
```

Add stub endpoints:

```python
@app.get("/catalog")
def list_catalog(tab: str = "video", q: str = "", platform: str = "", page: int = 1):
    db = get_db()
    page_size = 50
    offset = (page - 1) * page_size
    conditions = ["media_type = ?"]
    params = [tab]
    if q:
        conditions.append("title LIKE ?")
        params.append(f"%{q}%")
    if platform:
        conditions.append("platform = ?")
        params.append(platform)
    where = " AND ".join(conditions)
    total = db.execute(f"SELECT COUNT(*) FROM media WHERE {where}", params).fetchone()[0]
    rows = db.execute(
        f"SELECT * FROM media WHERE {where} ORDER BY created_at DESC LIMIT ? OFFSET ?",
        params + [page_size, offset],
    ).fetchall()
    db.close()
    return {
        "items": [dict(r) for r in rows],
        "total": total,
        "page": page,
        "page_size": page_size,
    }

@app.get("/channels")
def list_channels():
    db = get_db()
    rows = db.execute("SELECT * FROM channel_rules ORDER BY channel").fetchall()
    db.close()
    return [dict(r) for r in rows]

@app.put("/channels/{channel}")
def set_channel_rule(channel: str, body: dict):
    db = get_db()
    db.execute(
        "INSERT INTO channel_rules (channel, platform, mode) VALUES (?, ?, ?) ON CONFLICT(channel) DO UPDATE SET mode = ?, platform = ?",
        (channel, body.get("platform", ""), body.get("mode", "video"), body.get("mode", "video"), body.get("platform", "")),
    )
    db.commit()
    db.close()
    return {"status": "ok", "channel": channel, "mode": body.get("mode", "video")}
```

**Step 4: Run tests — expect PASS**

**Step 5: Commit**

```bash
git add apps/internet-archive/image-api/
git commit -m "feat: add media and channel_rules tables with catalog endpoints"
```

---

## Task 2: Sync Service — Pull from TubeArchivist and MeTube

**Files:**
- Create: `apps/internet-archive/image-api/sync.py`
- Create: `apps/internet-archive/image-api/test_sync.py`
- Modify: `apps/internet-archive/image-api/main.py`
- Modify: `apps/internet-archive/image-api/requirements.txt`

**Step 1: Add httpx to requirements.txt**

Add `httpx==0.27.0` (already present for tests, but now used at runtime too).

**Step 2: Write the failing test**

`test_sync.py`:

```python
import pytest
from sync import normalize_metube_item, normalize_ta_item

def test_normalize_metube_item():
    item = {
        "id": "123",
        "title": "Test Video",
        "url": "https://www.twitch.tv/user/clip/ClipId?filter=clips",
        "status": "finished",
        "filename": "Test Video.mp4",
        "size": 1234567,
        "timestamp": 1777524604914990556,
    }
    result = normalize_metube_item(item)
    assert result["source"] == "metube"
    assert result["platform"] == "twitch"
    assert result["title"] == "Test Video"
    assert result["url"] == "https://www.twitch.tv/user/clip/ClipId"

def test_normalize_metube_soundcloud():
    item = {
        "id": "456",
        "title": "Cool Track",
        "url": "https://soundcloud.com/artist/track",
        "status": "finished",
        "filename": "Cool Track.mp3",
        "size": 5000000,
        "timestamp": 1777524604914990556,
    }
    result = normalize_metube_item(item)
    assert result["media_type"] == "audio"
    assert result["platform"] == "soundcloud"

def test_normalize_ta_item():
    item = {
        "youtube_id": "dQw4w9WgXcQ",
        "title": "Never Gonna Give You Up",
        "published": "2009-10-25",
        "channel": {"channel_name": "Rick Astley"},
        "media_url": "/youtube/Rick Astley/Never Gonna Give You Up.mp4",
        "vid_thumb_url": "/cache/thumb/dQw4w9WgXcQ.jpg",
        "player": {"duration_str": "3:33"},
    }
    result = normalize_ta_item(item)
    assert result["source"] == "tubearchivist"
    assert result["platform"] == "youtube"
    assert result["channel"] == "Rick Astley"
    assert result["id"] == "ta_dQw4w9WgXcQ"
```

**Step 3: Run tests — expect FAIL**

**Step 4: Write sync.py**

```python
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

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
        from urllib.parse import urlunparse
        parsed = urlparse(url)
        return urlunparse(parsed._replace(query="", fragment=""))
    except Exception:
        return url


def normalize_metube_item(item):
    url = strip_query(item.get("url", ""))
    platform = detect_platform(url)
    filename = item.get("filename", "")
    is_audio = platform == "soundcloud" or filename.endswith((".mp3", ".m4a", ".ogg", ".opus", ".flac"))
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
        existing = db.execute("SELECT id FROM media WHERE id = ?", (normalized["id"],)).fetchone()
        if not existing:
            db.execute(
                "INSERT INTO media (id, source, media_type, title, url, platform, channel, thumbnail_path, file_path, audio_path, duration, file_size, tags, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
        existing = db.execute("SELECT id FROM media WHERE id = ?", (normalized["id"],)).fetchone()
        if not existing:
            db.execute(
                "INSERT INTO media (id, source, media_type, title, url, platform, channel, thumbnail_path, file_path, audio_path, duration, file_size, tags, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                tuple(normalized.values()),
            )
            count += 1
    db.commit()
    return count


def apply_channel_rules(db):
    rules = db.execute("SELECT channel, mode FROM channel_rules WHERE mode = 'audio_only'").fetchall()
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
```

**Step 5: Run tests — expect PASS**

**Step 6: Wire sync into main.py**

Add to `main.py`:
- `POST /catalog/sync` endpoint that calls `run_sync()`
- Background task on startup that syncs every 5 minutes using `asyncio`

```python
import asyncio
from sync import run_sync

@app.post("/catalog/sync")
def trigger_sync():
    db = get_db()
    count = run_sync(db)
    db.close()
    return {"status": "ok", "new_items": count}

@app.on_event("startup")
async def start_sync_loop():
    async def sync_loop():
        while True:
            try:
                db = get_db()
                run_sync(db)
                db.close()
            except Exception as e:
                print(f"[sync] Error: {e}")
            await asyncio.sleep(300)
    asyncio.create_task(sync_loop())
```

**Step 7: Commit**

```bash
git add apps/internet-archive/image-api/
git commit -m "feat: add sync service for TubeArchivist and MeTube"
```

---

## Task 3: Streaming Endpoints

**Files:**
- Modify: `apps/internet-archive/image-api/main.py`
- Modify: `apps/internet-archive/image-api/test_main.py`

**Step 1: Write the failing test**

```python
@pytest.mark.anyio
async def test_stream_not_found(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
    resp = await client.get("/stream/nonexistent")
    assert resp.status_code == 404

@pytest.mark.anyio
async def test_stream_media(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
    # Insert a fake media entry
    db_path = str(tmp_path / "metadata.db")
    monkeypatch.setenv("IMAGE_DB_PATH", db_path)
    test_file = tmp_path / "test.mp4"
    test_file.write_bytes(b"fake video content")
    from main import get_db
    db = get_db()
    db.execute(
        "INSERT INTO media (id, source, media_type, title, url, platform, channel, thumbnail_path, file_path, audio_path, duration, file_size, tags, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("test1", "metube", "video", "Test", "http://example.com", "twitch", "", "", str(test_file), "", 0, 18, "", "2026-01-01"),
    )
    db.commit()
    db.close()
    resp = await client.get("/stream/test1")
    assert resp.status_code == 200
```

**Step 2: Run tests — expect FAIL**

**Step 3: Implement streaming endpoints**

```python
from fastapi.responses import FileResponse, Response

@app.get("/stream/{media_id}")
def stream_media(media_id: str):
    db = get_db()
    row = db.execute("SELECT file_path FROM media WHERE id = ?", (media_id,)).fetchone()
    db.close()
    if not row or not row["file_path"]:
        return Response(status_code=404)
    path = Path(row["file_path"])
    if not path.exists():
        return Response(status_code=404)
    return FileResponse(path)

@app.get("/stream/{media_id}/audio")
def stream_audio(media_id: str):
    db = get_db()
    row = db.execute("SELECT audio_path FROM media WHERE id = ?", (media_id,)).fetchone()
    db.close()
    if not row or not row["audio_path"]:
        return Response(status_code=404)
    path = Path(row["audio_path"])
    if not path.exists():
        return Response(status_code=404)
    return FileResponse(path)

@app.get("/thumb/{media_id}")
def serve_thumb(media_id: str):
    db = get_db()
    row = db.execute("SELECT thumbnail_path FROM media WHERE id = ?", (media_id,)).fetchone()
    db.close()
    if not row or not row["thumbnail_path"]:
        return Response(status_code=404)
    path = Path(row["thumbnail_path"])
    if not path.exists():
        return Response(status_code=404)
    return FileResponse(path)

@app.get("/catalog/{media_id}")
def get_catalog_item(media_id: str):
    db = get_db()
    row = db.execute("SELECT * FROM media WHERE id = ?", (media_id,)).fetchone()
    db.close()
    if not row:
        return Response(status_code=404)
    return dict(row)
```

**Step 4: Run tests — expect PASS**

**Step 5: Commit**

```bash
git add apps/internet-archive/image-api/
git commit -m "feat: add streaming and catalog detail endpoints"
```

---

## Task 4: Audio Extraction via ffmpeg

**Files:**
- Create: `apps/internet-archive/image-api/audio.py`
- Create: `apps/internet-archive/image-api/test_audio.py`
- Modify: `apps/internet-archive/image-api/main.py`

**Step 1: Write the failing test**

`test_audio.py`:

```python
import pytest
from audio import build_ffmpeg_command, audio_output_path

def test_build_ffmpeg_command():
    cmd = build_ffmpeg_command("/data/video.mp4", "/data/video.mp3")
    assert cmd == ["ffmpeg", "-i", "/data/video.mp4", "-vn", "-acodec", "libmp3lame", "-q:a", "2", "-y", "/data/video.mp3"]

def test_audio_output_path():
    assert audio_output_path("/data/media/Cool Video.mp4") == "/data/media/Cool Video.mp3"
    assert audio_output_path("/data/media/track.webm") == "/data/media/track.mp3"
```

**Step 2: Run tests — expect FAIL**

**Step 3: Write audio.py**

```python
import subprocess
from pathlib import Path


def audio_output_path(video_path):
    p = Path(video_path)
    return str(p.with_suffix(".mp3"))


def build_ffmpeg_command(input_path, output_path):
    return [
        "ffmpeg", "-i", input_path,
        "-vn", "-acodec", "libmp3lame", "-q:a", "2",
        "-y", output_path,
    ]


def extract_audio(video_path):
    output = audio_output_path(video_path)
    cmd = build_ffmpeg_command(video_path, output)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {result.stderr}")
    return output
```

**Step 4: Run tests — expect PASS**

**Step 5: Add endpoint to main.py**

```python
from audio import extract_audio, audio_output_path

@app.post("/catalog/{media_id}/extract-audio")
def extract_media_audio(media_id: str):
    db = get_db()
    row = db.execute("SELECT file_path, audio_path FROM media WHERE id = ?", (media_id,)).fetchone()
    if not row or not row["file_path"]:
        db.close()
        return Response(status_code=404)
    if row["audio_path"]:
        db.close()
        return {"status": "already_extracted", "audio_path": row["audio_path"]}
    try:
        audio_path = extract_audio(row["file_path"])
        db.execute("UPDATE media SET audio_path = ? WHERE id = ?", (audio_path, media_id))
        db.commit()
        db.close()
        return {"status": "ok", "audio_path": audio_path}
    except Exception as e:
        db.close()
        return Response(status_code=500, content=str(e))
```

**Step 6: Commit**

```bash
git add apps/internet-archive/image-api/
git commit -m "feat: add audio extraction via ffmpeg"
```

---

## Task 5: Frontend — HTML/CSS/JS UI

**Files:**
- Create: `apps/internet-archive/image-api/static/index.html`
- Create: `apps/internet-archive/image-api/static/style.css`
- Create: `apps/internet-archive/image-api/static/app.js`
- Modify: `apps/internet-archive/image-api/main.py`

**Step 1: Mount static files in main.py**

```python
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse

# Add after app creation:
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/", response_class=HTMLResponse)
def index():
    return Path("static/index.html").read_text()
```

**Step 2: Write index.html**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hoarder</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <header>
    <h1>Hoarder</h1>
    <div class="controls">
      <input type="search" id="search" placeholder="Search...">
      <select id="platform-filter">
        <option value="">All Sources</option>
        <option value="youtube">YouTube</option>
        <option value="soundcloud">SoundCloud</option>
        <option value="twitch">Twitch</option>
      </select>
      <button id="sync-btn" title="Sync now">↻</button>
      <button id="settings-btn" title="Settings">⚙</button>
    </div>
  </header>
  <nav class="tabs">
    <button class="tab active" data-tab="video">Videos</button>
    <button class="tab" data-tab="audio">Music</button>
    <button class="tab" data-tab="image">Images</button>
  </nav>
  <main id="content"></main>
  <div id="now-playing" class="now-playing hidden">
    <audio id="global-audio" controls></audio>
    <span id="now-playing-title"></span>
  </div>
  <dialog id="settings-dialog">
    <h2>Settings</h2>
    <div id="channel-rules"></div>
    <button id="close-settings">Close</button>
  </dialog>
  <script src="/static/app.js"></script>
</body>
</html>
```

**Step 3: Write style.css**

A clean, dark-themed UI with:
- Header with search and filters
- Tab bar
- Card grid for videos (4 columns)
- List layout for music
- Masonry grid for images
- Now-playing bar fixed to bottom
- ~200 lines of CSS

**Step 4: Write app.js**

Core functionality:
- Tab switching — fetches `/catalog?tab=X` on tab click
- Search — debounced input that re-fetches with `q=` param
- Platform filter — re-fetches with `platform=` param
- Video cards — thumbnail, title, channel, duration; click expands inline `<video>` player with "Extract Audio" button
- Music list — rows with play button; clicking plays via the global `<audio>` element in the now-playing bar
- Image grid — thumbnails; click expands overlay
- Sync button — POSTs to `/catalog/sync`
- Settings dialog — fetches `/channels`, renders dropdown per channel
- Extract audio button — POSTs to `/catalog/{id}/extract-audio`
- ~300 lines of JS

**Step 5: Commit**

```bash
git add apps/internet-archive/image-api/static/
git commit -m "feat: add Hoarder catalog frontend with tabs, playback, and settings"
```

---

## Task 6: Update Dockerfile and docker-compose

**Files:**
- Modify: `apps/internet-archive/image-api/Dockerfile`
- Modify: `apps/internet-archive/docker-compose.yml`

**Step 1: Update Dockerfile**

```dockerfile
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py sync.py audio.py ./
COPY static/ static/
EXPOSE 8082
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8082"]
```

**Step 2: Update docker-compose.yml**

Update the `image-api` service:

```yaml
  image-api:
    build: ./image-api
    container_name: hoarder-catalog
    restart: unless-stopped
    ports:
      - "8082:8082"
    volumes:
      - images:/data/images
      - ta-media:/data/youtube:ro
      - metube-downloads:/data/media:ro
    environment:
      - TA_API_URL=http://tubearchivist:8000
      - TA_API_KEY=${TA_API_KEY}
      - METUBE_API_URL=http://metube:8081
```

**Step 3: Commit**

```bash
git add apps/internet-archive/
git commit -m "feat: update Dockerfile with ffmpeg and docker-compose with volume mounts"
```

---

## Task 7: Deploy to NAS

**Step 1: Copy updated files to NAS**

```bash
scp apps/internet-archive/docker-compose.yml mackieg@newnas.local:~/internet-archive/
scp apps/internet-archive/image-api/main.py apps/internet-archive/image-api/sync.py apps/internet-archive/image-api/audio.py apps/internet-archive/image-api/Dockerfile apps/internet-archive/image-api/requirements.txt mackieg@newnas.local:~/internet-archive/image-api/
scp -r apps/internet-archive/image-api/static/ mackieg@newnas.local:~/internet-archive/image-api/static/
```

**Step 2: Rebuild and restart**

```bash
ssh mackieg@newnas.local 'cd ~/internet-archive && docker compose up -d --build image-api'
```

**Step 3: Verify**

```bash
curl http://newnas.local:8082/health
curl http://newnas.local:8082/catalog?tab=video
```

**Step 4: Trigger initial sync**

```bash
curl -X POST http://newnas.local:8082/catalog/sync
```

---

## Summary

| Task | What | Testable |
|------|------|----------|
| 1 | Database schema + catalog/channel endpoints | Yes |
| 2 | Sync service (TubeArchivist + MeTube) | Yes |
| 3 | Streaming + detail endpoints | Yes |
| 4 | Audio extraction via ffmpeg | Yes |
| 5 | Frontend HTML/CSS/JS UI | Manual |
| 6 | Dockerfile + docker-compose updates | Validate |
| 7 | Deploy to NAS | Manual |
