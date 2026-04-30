# Hoarder Catalog — Unified Media Browser

## Overview

Expand the existing image-api (port 8082) into a unified media catalog and player for all archived content on the NAS. Aggregates metadata from TubeArchivist, MeTube, and the local image archive into a single SQLite database with a browsable web UI and built-in playback.

## Data Sources

- **TubeArchivist API** (port 8000) — YouTube videos, metadata, thumbnails
- **MeTube `/history`** (port 8081) — Twitch clips, SoundCloud tracks, other downloads
- **Local SQLite DB** — Images (existing), channel rules, audio extractions

## Data Model

### `media` table

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Unique identifier |
| source | TEXT | "tubearchivist", "metube", "local" |
| media_type | TEXT | "video", "audio", "image" |
| title | TEXT | Title of the media |
| url | TEXT | Original source URL |
| platform | TEXT | "youtube", "soundcloud", "twitch", etc. |
| channel | TEXT | Channel or artist name |
| thumbnail_path | TEXT | Path to thumbnail on disk |
| file_path | TEXT | Path to media file on NAS |
| audio_path | TEXT | Path to extracted audio (NULL if not extracted) |
| duration | INTEGER | Duration in seconds |
| file_size | INTEGER | File size in bytes |
| tags | TEXT | Comma-separated tags |
| created_at | TEXT | When it was archived |

### `channel_rules` table

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| channel | TEXT UNIQUE | Channel or artist name |
| platform | TEXT | "youtube", "soundcloud", "twitch" |
| mode | TEXT | "video" (default) or "audio_only" |

### Sync Strategy

A background task runs every 5 minutes:
1. Pulls new entries from TubeArchivist API and MeTube `/history`
2. Inserts new items into the `media` table
3. Applies channel rules (auto-extracts audio for "audio_only" channels)
4. Tags SoundCloud downloads as `media_type: "audio"` automatically

## API Endpoints

### Existing (unchanged)

- `GET /health`
- `POST /upload` — image upload
- `GET /images` — legacy image list

### Catalog

- `GET /catalog?tab=video|audio|image&q=search&platform=youtube&page=1` — paginated media list
- `GET /catalog/{id}` — single item detail
- `POST /catalog/sync` — trigger manual sync
- `POST /catalog/{id}/extract-audio` — extract audio from video via ffmpeg

### Channel Rules

- `GET /channels` — list all channels with rules
- `PUT /channels/{channel}` — set channel rule (e.g. `{"mode": "audio_only"}`)

### Streaming

- `GET /stream/{id}` — stream media file with range request support
- `GET /stream/{id}/audio` — stream extracted audio
- `GET /thumb/{id}` — serve thumbnail

## Frontend UI

Single-page app served at `GET /`. Plain HTML/CSS/JS, no framework.

### Header

"Hoarder" title, search bar, source filter dropdown (All / YouTube / SoundCloud / Twitch).

### Videos Tab

- Card grid with thumbnail, title, channel, duration, platform badge, date
- Click card to expand inline with HTML5 `<video>` player
- "Extract Audio" button on each card
- Music note icon on cards with extracted audio

### Music Tab

- Playlist-style list with title, artist/channel, duration, platform badge
- Inline `<audio>` player with play/pause per row
- SoundCloud downloads and extracted YouTube audio both appear here
- "Now playing" bar at bottom that persists across navigation

### Images Tab

- Masonry grid of thumbnails
- Click to expand full-size with metadata overlay (source URL, tags, date)

### Settings (gear icon)

- Channel rules list with dropdown per channel ("video" / "audio_only")
- Manual sync button
- Last sync timestamp

## Audio Extraction

### On-demand

1. User clicks "Extract Audio" on a video
2. Server runs `ffmpeg -i <video_path> -vn -acodec libmp3lame -q:a 2 <audio_path>`
3. Audio saved as `{filename}.mp3` alongside video
4. `media.audio_path` updated, item appears in Music tab

### Channel rules

1. New items checked against `channel_rules` after sync
2. "audio_only" channels auto-extract audio from new videos
3. Video file kept, but `media_type` set to "audio" for Music tab display

### SoundCloud

- Already downloaded as audio by MeTube
- Tagged as `media_type: "audio"` during sync automatically

## Deployment Changes

### Dockerfile

- Base: `python:3.12-slim`
- Add `ffmpeg` package
- Mount TubeArchivist and MeTube volumes as read-only

### docker-compose.yml updates

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

## Future Enhancements

- AI auto-tagging of images
- Full-text search across all metadata
- Playlist creation
- Bulk audio extraction
- Download progress tracking in real-time
