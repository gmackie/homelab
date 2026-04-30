# Personal Internet Archive

## Overview

A browser extension + NAS-based download system that captures video, audio, and images from browsing activity and archives them on `newnas.local`.

## Components

### Browser Extension (Firefox + Chrome)

Manifest V3, single codebase using WebExtensions API. Loaded as unpacked extension in both browsers.

**Background service worker:**
- Handles URL submission, cookie extraction, and NAS communication
- Extracts cookies via `browser.cookies.getAll()` in Netscape format
- Routes requests to the correct NAS service based on URL domain
- Downloads image blobs for the context menu save feature

**Content script:**
- Injected on supported sites
- Extracts page metadata (title, channel name, duration)
- Does not modify the page

**Popup UI:**
- Shows current page status and one-click archive button
- Manual URL paste field for arbitrary submissions
- Settings page for NAS endpoint, API keys, domain list

**Context menu:**
- Right-click any image → "Save to NAS"
- Optional "Save to NAS with tag..." sub-item with a small prompt for a tag string
- Extension downloads the image blob and uploads it directly

**Auto-detect mode:**
- When enabled, extension icon shows a colored badge on supported pages
- No automatic submission — visual nudge for one-click archiving

**Keyboard shortcut:**
- Default `Alt+Shift+A` to archive current page without opening popup

**URL routing:**
- `youtube.com`, `youtu.be` → TubeArchivist API
- Image right-click → Image archive API
- Everything else → MeTube API

**Supported domains (initial):**
- `youtube.com`, `youtu.be`
- `soundcloud.com`
- `twitch.tv`, `clips.twitch.tv`
- User-editable list in settings

**Permissions:**
- `cookies` — read domain cookies for authenticated downloads
- `contextMenus` — right-click "Save to NAS"
- `activeTab` — read page metadata
- `notifications` — brief submit/error toasts
- Host permissions for NAS URL and supported sites

**Storage:**
- `browser.storage.sync` — settings (follow across browser instances)
- `browser.storage.local` — API keys (stay on-device)

### TubeArchivist (NAS)

YouTube-focused download and media library service.

- Web UI + API on port 8000
- Requires Elasticsearch (search index) and Redis (task queue)
- Handles YouTube channel tracking, metadata, thumbnails, search
- Built-in cookie management via API
- Volume: `/data/archive/youtube/`

### MeTube (NAS)

Generic yt-dlp frontend for non-YouTube content.

- Web UI + API on port 8081
- Handles SoundCloud, Twitch, and any other yt-dlp-supported site
- Cookies written per-request from extension-provided data
- Volume: `/data/archive/media/`

### Image Archive API (NAS)

Custom lightweight service for meme/image archiving.

- Python/FastAPI, ~100 lines
- Accepts multipart image upload + JSON metadata
- Metadata: source URL, page title, timestamp, optional tags
- SQLite database for metadata indexing
- Port 8082
- Volume: `/data/archive/images/`

## Data Flow

### Video/Audio Archive

1. User visits a YouTube/SoundCloud/Twitch page
2. Content script extracts page metadata (title, channel, URL)
3. Extension icon lights up with badge
4. User clicks "Archive" (button, icon, or keyboard shortcut)
5. Background worker extracts cookies for that domain
6. POSTs URL + cookies + metadata to appropriate NAS service
7. NAS service queues download and processes with yt-dlp
8. Extension shows brief "Submitted!" notification

### Image Save

1. User right-clicks an image on any page
2. Selects "Save to NAS" or "Save to NAS with tag..."
3. Optional tag prompt appears
4. Extension downloads the image blob in background worker
5. POSTs image binary + metadata to image archive API
6. API stores file and indexes metadata in SQLite
7. Brief "Saved!" notification

### Cookie Handling

- Cookies sent with every request — always fresh
- TubeArchivist: updated via its API
- MeTube: cookies.txt written before each download
- No stale cookie issues, no periodic sync needed

### Failure Handling

- Fire and forget from extension side
- TubeArchivist and MeTube have built-in retry logic and failure UIs
- Image API returns success/fail; extension shows error notification on failure

## Deployment

### NAS Services (newnas.local)

Single `docker-compose.yml` with all services:
- TubeArchivist + Elasticsearch + Redis
- MeTube
- Image archive API (custom Dockerfile)
- All volumes under `/data/archive/`
- Accessible via Tailscale — no port forwarding needed

### Ports

| Service | Port |
|---------|------|
| TubeArchivist | 8000 |
| MeTube | 8081 |
| Image Archive API | 8082 |

### Repository Location

```
apps/internet-archive/
├── docker-compose.yml
├── image-api/
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
└── extension/
    ├── manifest.json
    ├── background.js
    ├── content.js
    ├── popup/
    └── icons/
```

## Future Enhancements

- AI auto-tagging of images based on content and source context
- TubeArchivist subscription monitoring (auto-download new channel videos)
- Full-text search across all archived metadata
- Deduplication
