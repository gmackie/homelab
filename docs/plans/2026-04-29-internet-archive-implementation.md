# Personal Internet Archive Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a browser extension + NAS download system that archives video, audio, and images from browsing activity onto `newnas.local`.

**Architecture:** Browser extension (Manifest V3, Firefox + Chrome) captures URLs and cookies, routing YouTube to TubeArchivist, other media to MeTube, and images to a custom FastAPI service. All NAS services run via Docker Compose, accessible over Tailscale.

**Tech Stack:** JavaScript (WebExtensions API, Manifest V3), Python (FastAPI, SQLite), Docker Compose, TubeArchivist, MeTube, yt-dlp

**Repos:**
- `homelab` (`/Volumes/dev/homelab`) — NAS services at `apps/internet-archive/`
- `hoarder-extension` (`/Volumes/dev/hoarder-extension`) — browser extension

---

## Task 1: Docker Compose for NAS Services

**Files:**
- Create: `apps/internet-archive/docker-compose.yml`

**Step 1: Write docker-compose.yml**

```yaml
services:
  tubearchivist:
    image: bbilly1/tubearchivist
    container_name: tubearchivist
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      - ta-media:/youtube
      - ta-cache:/cache
    environment:
      - ES_URL=http://archivist-es:9200
      - REDIS_CON=redis://archivist-redis:6379
      - HOST_UID=1000
      - HOST_GID=1000
      - TA_HOST=newnas.local
      - TA_USERNAME=tubearchivist
      - TA_PASSWORD=${TA_PASSWORD:-changeme}
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD:-changeme}
      - TZ=America/Los_Angeles
    depends_on:
      - archivist-es
      - archivist-redis
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  archivist-redis:
    image: redis/redis-stack-server
    container_name: archivist-redis
    restart: unless-stopped
    expose:
      - "6379"
    volumes:
      - ta-redis:/data

  archivist-es:
    image: bbilly1/tubearchivist-es
    container_name: archivist-es
    restart: unless-stopped
    environment:
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD:-changeme}
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
      - xpack.security.enabled=true
      - discovery.type=single-node
      - path.repo=/usr/share/elasticsearch/data/snapshot
    ulimits:
      memlock:
        soft: -1
        hard: -1
    expose:
      - "9200"
    volumes:
      - ta-es:/usr/share/elasticsearch/data

  metube:
    image: ghcr.io/alexta69/metube
    container_name: metube
    restart: unless-stopped
    ports:
      - "8081:8081"
    volumes:
      - metube-downloads:/downloads
    environment:
      - CORS_ALLOWED_ORIGINS=*

  image-api:
    build: ./image-api
    container_name: image-api
    restart: unless-stopped
    ports:
      - "8082:8082"
    volumes:
      - images:/data/images

volumes:
  ta-media:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/archive/youtube
  ta-cache:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/archive/youtube-cache
  ta-redis:
  ta-es:
  metube-downloads:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/archive/media
  images:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/archive/images
```

**Step 2: Validate compose file syntax**

Run: `docker compose -f apps/internet-archive/docker-compose.yml config --quiet`
Expected: no output (valid)

**Step 3: Commit**

```bash
git add apps/internet-archive/docker-compose.yml
git commit -m "feat: add docker-compose for internet archive NAS services"
```

---

## Task 2: Image Archive API — Project Setup

**Files:**
- Create: `apps/internet-archive/image-api/requirements.txt`
- Create: `apps/internet-archive/image-api/main.py`
- Create: `apps/internet-archive/image-api/Dockerfile`
- Create: `apps/internet-archive/image-api/test_main.py`

**Step 1: Write requirements.txt**

```
fastapi==0.115.0
uvicorn==0.30.0
python-multipart==0.0.9
aiosqlite==0.20.0
pytest==8.3.0
httpx==0.27.0
```

**Step 2: Write the failing test**

`apps/internet-archive/image-api/test_main.py`:

```python
import io
import pytest
from httpx import ASGITransport, AsyncClient
from main import app

@pytest.fixture
def anyio_backend():
    return "asyncio"

@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

@pytest.mark.anyio
async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}

@pytest.mark.anyio
async def test_upload_image(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    fake_png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
    resp = await client.post(
        "/upload",
        files={"image": ("meme.png", io.BytesIO(fake_png), "image/png")},
        data={
            "source_url": "https://reddit.com/r/memes/abc",
            "page_title": "Funny meme",
            "tags": "cursed,reaction",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "saved"
    assert body["filename"] == "meme.png"
    assert "id" in body

@pytest.mark.anyio
async def test_upload_image_no_tags(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    fake_png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
    resp = await client.post(
        "/upload",
        files={"image": ("no-tag.png", io.BytesIO(fake_png), "image/png")},
        data={
            "source_url": "https://twitter.com/post/123",
            "page_title": "A tweet",
        },
    )
    assert resp.status_code == 200
    assert resp.json()["tags"] == []

@pytest.mark.anyio
async def test_list_images(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    fake_png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
    await client.post(
        "/upload",
        files={"image": ("list-test.png", io.BytesIO(fake_png), "image/png")},
        data={"source_url": "https://example.com", "page_title": "Test"},
    )
    resp = await client.get("/images")
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) >= 1
    assert items[0]["source_url"] == "https://example.com"
```

**Step 3: Run tests to verify they fail**

Run: `cd apps/internet-archive/image-api && pip install -r requirements.txt && pytest test_main.py -v`
Expected: FAIL — `main` module doesn't exist yet

**Step 4: Write main.py**

```python
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DB_PATH = os.environ.get("IMAGE_DB_PATH", "/data/images/metadata.db")
STORAGE_PATH = os.environ.get("IMAGE_STORAGE_PATH", "/data/images/files")


def get_db():
    path = Path(DB_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    conn.execute(
        """CREATE TABLE IF NOT EXISTS images (
            id TEXT PRIMARY KEY,
            filename TEXT NOT NULL,
            source_url TEXT,
            page_title TEXT,
            tags TEXT,
            created_at TEXT NOT NULL
        )"""
    )
    conn.commit()
    return conn


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/upload")
async def upload_image(
    image: UploadFile = File(...),
    source_url: str = Form(""),
    page_title: str = Form(""),
    tags: str = Form(""),
):
    storage = Path(STORAGE_PATH)
    storage.mkdir(parents=True, exist_ok=True)

    image_id = uuid.uuid4().hex[:12]
    ext = Path(image.filename or "image").suffix or ".png"
    stored_name = f"{image_id}{ext}"

    content = await image.read()
    (storage / stored_name).write_bytes(content)

    tag_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []
    now = datetime.now(timezone.utc).isoformat()

    db = get_db()
    db.execute(
        "INSERT INTO images (id, filename, source_url, page_title, tags, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        (image_id, image.filename, source_url, page_title, ",".join(tag_list), now),
    )
    db.commit()
    db.close()

    return {
        "status": "saved",
        "id": image_id,
        "filename": image.filename,
        "tags": tag_list,
    }


@app.get("/images")
def list_images():
    db = get_db()
    rows = db.execute("SELECT * FROM images ORDER BY created_at DESC").fetchall()
    db.close()
    return [
        {
            "id": r["id"],
            "filename": r["filename"],
            "source_url": r["source_url"],
            "page_title": r["page_title"],
            "tags": [t for t in r["tags"].split(",") if t] if r["tags"] else [],
            "created_at": r["created_at"],
        }
        for r in rows
    ]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8082)
```

**Step 5: Run tests to verify they pass**

Run: `cd apps/internet-archive/image-api && pytest test_main.py -v`
Expected: all 4 tests PASS

**Step 6: Write Dockerfile**

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8082
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8082"]
```

**Step 7: Commit**

```bash
git add apps/internet-archive/image-api/
git commit -m "feat: add image archive API with FastAPI and SQLite"
```

---

## Task 3: Initialize Browser Extension Repo

**Repo:** `/Volumes/dev/hoarder-extension`

**Files:**
- Create: `package.json`
- Create: `manifest.json`
- Create: `README.md`

**Step 1: Initialize repo**

```bash
mkdir -p /Volumes/dev/hoarder-extension
cd /Volumes/dev/hoarder-extension
git init
```

**Step 2: Write package.json**

```json
{
  "name": "hoarder-extension",
  "version": "0.1.0",
  "description": "Browser extension for archiving video, audio, and images to a NAS",
  "private": true,
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "build": "node build.js",
    "lint": "eslint src/"
  },
  "devDependencies": {
    "vitest": "^3.0.0",
    "eslint": "^9.0.0",
    "webextension-polyfill": "^0.12.0"
  }
}
```

**Step 3: Write manifest.json (Manifest V3)**

```json
{
  "manifest_version": 3,
  "name": "Hoarder",
  "version": "0.1.0",
  "description": "Archive video, audio, and images to your NAS",
  "permissions": [
    "cookies",
    "contextMenus",
    "activeTab",
    "notifications",
    "storage"
  ],
  "host_permissions": [
    "https://*.youtube.com/*",
    "https://*.youtu.be/*",
    "https://*.soundcloud.com/*",
    "https://*.twitch.tv/*",
    "http://newnas.local/*",
    "<all_urls>"
  ],
  "background": {
    "service_worker": "src/background.js",
    "type": "module"
  },
  "content_scripts": [
    {
      "matches": [
        "https://*.youtube.com/*",
        "https://*.soundcloud.com/*",
        "https://*.twitch.tv/*"
      ],
      "js": ["src/content.js"]
    }
  ],
  "action": {
    "default_popup": "src/popup/popup.html",
    "default_icon": {
      "16": "icons/icon-16.png",
      "48": "icons/icon-48.png",
      "128": "icons/icon-128.png"
    }
  },
  "icons": {
    "16": "icons/icon-16.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  },
  "commands": {
    "archive-page": {
      "suggested_key": {
        "default": "Alt+Shift+A"
      },
      "description": "Archive current page"
    }
  }
}
```

**Step 4: Create placeholder icon**

```bash
mkdir -p icons
# Generate simple placeholder SVG converted to PNG later
# For now, create a minimal 1x1 PNG as placeholder
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > icons/icon-16.png
cp icons/icon-16.png icons/icon-48.png
cp icons/icon-16.png icons/icon-128.png
```

**Step 5: Commit**

```bash
git add .
git commit -m "feat: initialize hoarder extension with manifest v3"
```

---

## Task 4: Background Service Worker — Config & Cookie Utilities

**Repo:** `/Volumes/dev/hoarder-extension`

**Files:**
- Create: `src/config.js`
- Create: `src/cookies.js`
- Create: `tests/cookies.test.js`

**Step 1: Write the failing test**

`tests/cookies.test.js`:

```javascript
import { describe, it, expect } from "vitest";
import { toNetscapeCookieString } from "../src/cookies.js";

describe("toNetscapeCookieString", () => {
  it("converts browser cookies to Netscape format", () => {
    const cookies = [
      {
        domain: ".youtube.com",
        httpOnly: false,
        path: "/",
        secure: true,
        expirationDate: 1735689600,
        name: "PREF",
        value: "tz=America.Los_Angeles",
      },
    ];
    const result = toNetscapeCookieString(cookies);
    const lines = result.trim().split("\n");
    expect(lines[0]).toBe("# Netscape HTTP Cookie File");
    expect(lines[1]).toContain(".youtube.com");
    expect(lines[1]).toContain("PREF");
    expect(lines[1]).toContain("tz=America.Los_Angeles");
  });

  it("handles multiple cookies", () => {
    const cookies = [
      { domain: ".youtube.com", httpOnly: true, path: "/", secure: true, expirationDate: 0, name: "A", value: "1" },
      { domain: ".youtube.com", httpOnly: false, path: "/", secure: false, expirationDate: 0, name: "B", value: "2" },
    ];
    const result = toNetscapeCookieString(cookies);
    const dataLines = result.trim().split("\n").filter((l) => !l.startsWith("#"));
    expect(dataLines).toHaveLength(2);
  });

  it("returns header only for empty array", () => {
    const result = toNetscapeCookieString([]);
    expect(result.trim()).toBe("# Netscape HTTP Cookie File");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd /Volumes/dev/hoarder-extension && npx vitest run tests/cookies.test.js`
Expected: FAIL — module not found

**Step 3: Write src/cookies.js**

```javascript
export function toNetscapeCookieString(cookies) {
  const lines = ["# Netscape HTTP Cookie File"];
  for (const c of cookies) {
    const domain = c.domain.startsWith(".") ? c.domain : `.${c.domain}`;
    const includeSubdomains = domain.startsWith(".") ? "TRUE" : "FALSE";
    const secure = c.secure ? "TRUE" : "FALSE";
    const httpOnly = c.httpOnly ? "#HttpOnly_" : "";
    const expiry = Math.floor(c.expirationDate || 0);
    lines.push(
      `${httpOnly}${domain}\t${includeSubdomains}\t${c.path}\t${secure}\t${expiry}\t${c.name}\t${c.value}`
    );
  }
  return lines.join("\n");
}

export async function getCookiesForDomain(domain) {
  const cookies = await chrome.cookies.getAll({ domain });
  return toNetscapeCookieString(cookies);
}
```

**Step 4: Write src/config.js**

```javascript
const DEFAULTS = {
  nasBaseUrl: "http://newnas.local",
  tubeArchivistPort: 8000,
  metubePort: 8081,
  imageApiPort: 8082,
  taApiKey: "",
  autoDetect: true,
  supportedDomains: [
    "youtube.com",
    "youtu.be",
    "soundcloud.com",
    "twitch.tv",
    "clips.twitch.tv",
  ],
};

export async function getConfig() {
  const stored = await chrome.storage.local.get(DEFAULTS);
  return stored;
}

export async function saveConfig(config) {
  await chrome.storage.local.set(config);
}

export function getServiceUrl(config, service) {
  const ports = {
    tubearchivist: config.tubeArchivistPort,
    metube: config.metubePort,
    imageApi: config.imageApiPort,
  };
  return `${config.nasBaseUrl}:${ports[service]}`;
}

export function getTargetService(url) {
  try {
    const hostname = new URL(url).hostname;
    if (hostname.includes("youtube.com") || hostname.includes("youtu.be")) {
      return "tubearchivist";
    }
    return "metube";
  } catch {
    return "metube";
  }
}
```

**Step 5: Run tests to verify they pass**

Run: `cd /Volumes/dev/hoarder-extension && npx vitest run tests/cookies.test.js`
Expected: all 3 tests PASS

**Step 6: Commit**

```bash
git add src/config.js src/cookies.js tests/cookies.test.js
git commit -m "feat: add config module and cookie extraction utility"
```

---

## Task 5: Background Service Worker — URL Submission

**Repo:** `/Volumes/dev/hoarder-extension`

**Files:**
- Create: `src/api.js`
- Create: `tests/api.test.js`

**Step 1: Write the failing test**

`tests/api.test.js`:

```javascript
import { describe, it, expect, vi } from "vitest";
import { buildTubeArchivistPayload, buildMetubePayload } from "../src/api.js";

describe("buildTubeArchivistPayload", () => {
  it("builds correct payload for YouTube URL", () => {
    const payload = buildTubeArchivistPayload("https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    expect(payload).toEqual({
      data: [{ youtube_id: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", status: "pending" }],
    });
  });
});

describe("buildMetubePayload", () => {
  it("builds correct payload for generic URL", () => {
    const payload = buildMetubePayload("https://soundcloud.com/artist/track");
    expect(payload).toEqual({
      url: "https://soundcloud.com/artist/track",
      quality: "best",
    });
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd /Volumes/dev/hoarder-extension && npx vitest run tests/api.test.js`
Expected: FAIL — module not found

**Step 3: Write src/api.js**

```javascript
import { getCookiesForDomain } from "./cookies.js";
import { getConfig, getServiceUrl, getTargetService } from "./config.js";

export function buildTubeArchivistPayload(url) {
  return {
    data: [{ youtube_id: url, status: "pending" }],
  };
}

export function buildMetubePayload(url) {
  return {
    url,
    quality: "best",
  };
}

export async function submitUrl(url) {
  const config = await getConfig();
  const service = getTargetService(url);
  const domain = new URL(url).hostname.replace(/^www\./, "");
  const cookieString = await getCookiesForDomain(domain);

  if (service === "tubearchivist") {
    const baseUrl = getServiceUrl(config, "tubearchivist");

    await fetch(`${baseUrl}/api/appsettings/cookie/`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Token ${config.taApiKey}`,
      },
      body: JSON.stringify({ cookie: cookieString }),
    });

    const resp = await fetch(`${baseUrl}/api/download/?autostart=true`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Token ${config.taApiKey}`,
      },
      body: JSON.stringify(buildTubeArchivistPayload(url)),
    });
    return resp.ok;
  }

  const baseUrl = getServiceUrl(config, "metube");

  const cookieBlob = new Blob([cookieString], { type: "text/plain" });
  const cookieForm = new FormData();
  cookieForm.append("cookies", cookieBlob, "cookies.txt");
  await fetch(`${baseUrl}/upload-cookies`, {
    method: "POST",
    body: cookieForm,
  });

  const resp = await fetch(`${baseUrl}/add`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(buildMetubePayload(url)),
  });
  return resp.ok;
}

export async function uploadImage(imageBlob, filename, metadata) {
  const config = await getConfig();
  const baseUrl = getServiceUrl(config, "imageApi");

  const form = new FormData();
  form.append("image", imageBlob, filename);
  form.append("source_url", metadata.sourceUrl || "");
  form.append("page_title", metadata.pageTitle || "");
  if (metadata.tags) {
    form.append("tags", metadata.tags);
  }

  const resp = await fetch(`${baseUrl}/upload`, {
    method: "POST",
    body: form,
  });
  return resp.ok;
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /Volumes/dev/hoarder-extension && npx vitest run tests/api.test.js`
Expected: all 2 tests PASS

**Step 5: Commit**

```bash
git add src/api.js tests/api.test.js
git commit -m "feat: add API submission module for TubeArchivist, MeTube, and image API"
```

---

## Task 6: Background Service Worker — Main Entry Point

**Repo:** `/Volumes/dev/hoarder-extension`

**Files:**
- Create: `src/background.js`

**Step 1: Write background.js**

```javascript
import { submitUrl, uploadImage } from "./api.js";
import { getConfig, getTargetService } from "./config.js";

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === "save-to-nas" || info.menuItemId === "save-to-nas-tagged") {
    try {
      let tags = "";
      if (info.menuItemId === "save-to-nas-tagged") {
        // Tags will be collected via a content script prompt
        const [result] = await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          func: () => prompt("Enter tags (comma-separated):"),
        });
        tags = result?.result || "";
      }

      const response = await fetch(info.srcUrl);
      const blob = await response.blob();
      const filename = info.srcUrl.split("/").pop().split("?")[0] || "image.png";

      const ok = await uploadImage(blob, filename, {
        sourceUrl: info.srcUrl,
        pageTitle: tab.title || "",
        tags,
      });

      showNotification(ok ? "Saved!" : "Save failed");
    } catch (e) {
      showNotification("Save failed: " + e.message);
    }
  }
});

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "save-to-nas",
    title: "Save to NAS",
    contexts: ["image"],
  });
  chrome.contextMenus.create({
    id: "save-to-nas-tagged",
    title: "Save to NAS with tag...",
    contexts: ["image"],
  });
});

chrome.action.onClicked.addListener(async (tab) => {
  await archiveCurrentTab(tab);
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command === "archive-page") {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) await archiveCurrentTab(tab);
  }
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (changeInfo.status !== "complete" || !tab.url) return;
  const config = await getConfig();
  if (!config.autoDetect) return;

  const hostname = new URL(tab.url).hostname;
  const isSupported = config.supportedDomains.some((d) => hostname.includes(d));

  if (isSupported) {
    chrome.action.setBadgeText({ text: "●", tabId });
    chrome.action.setBadgeBackgroundColor({ color: "#4CAF50", tabId });
  } else {
    chrome.action.setBadgeText({ text: "", tabId });
  }
});

async function archiveCurrentTab(tab) {
  if (!tab.url) return;
  try {
    const ok = await submitUrl(tab.url);
    showNotification(ok ? "Submitted!" : "Submit failed");
  } catch (e) {
    showNotification("Submit failed: " + e.message);
  }
}

function showNotification(message) {
  chrome.notifications.create({
    type: "basic",
    iconUrl: "icons/icon-128.png",
    title: "Hoarder",
    message,
  });
}
```

**Step 2: Commit**

```bash
git add src/background.js
git commit -m "feat: add background service worker with context menus and auto-detect"
```

---

## Task 7: Content Script — Metadata Extraction

**Repo:** `/Volumes/dev/hoarder-extension`

**Files:**
- Create: `src/content.js`
- Create: `tests/content.test.js`

**Step 1: Write the failing test**

`tests/content.test.js`:

```javascript
import { describe, it, expect } from "vitest";
import { extractMetadata } from "../src/content.js";

describe("extractMetadata", () => {
  it("extracts YouTube metadata", () => {
    const meta = extractMetadata(
      "https://www.youtube.com/watch?v=abc123",
      "Cool Video - YouTube",
    );
    expect(meta).toEqual({
      url: "https://www.youtube.com/watch?v=abc123",
      title: "Cool Video - YouTube",
      platform: "youtube",
    });
  });

  it("extracts SoundCloud metadata", () => {
    const meta = extractMetadata(
      "https://soundcloud.com/artist/track",
      "Track by Artist",
    );
    expect(meta.platform).toBe("soundcloud");
  });

  it("extracts Twitch metadata", () => {
    const meta = extractMetadata(
      "https://clips.twitch.tv/clip-id",
      "Funny clip - Twitch",
    );
    expect(meta.platform).toBe("twitch");
  });

  it("returns unknown for unsupported sites", () => {
    const meta = extractMetadata("https://example.com", "Example");
    expect(meta.platform).toBe("unknown");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd /Volumes/dev/hoarder-extension && npx vitest run tests/content.test.js`
Expected: FAIL — module not found

**Step 3: Write src/content.js**

```javascript
export function extractMetadata(url, title) {
  const hostname = new URL(url).hostname;
  let platform = "unknown";

  if (hostname.includes("youtube.com") || hostname.includes("youtu.be")) {
    platform = "youtube";
  } else if (hostname.includes("soundcloud.com")) {
    platform = "soundcloud";
  } else if (hostname.includes("twitch.tv")) {
    platform = "twitch";
  }

  return { url, title, platform };
}

if (typeof chrome !== "undefined" && chrome.runtime) {
  const metadata = extractMetadata(window.location.href, document.title);
  chrome.runtime.sendMessage({ type: "page-metadata", ...metadata });
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /Volumes/dev/hoarder-extension && npx vitest run tests/content.test.js`
Expected: all 4 tests PASS

**Step 5: Commit**

```bash
git add src/content.js tests/content.test.js
git commit -m "feat: add content script for page metadata extraction"
```

---

## Task 8: Popup UI

**Repo:** `/Volumes/dev/hoarder-extension`

**Files:**
- Create: `src/popup/popup.html`
- Create: `src/popup/popup.css`
- Create: `src/popup/popup.js`

**Step 1: Write popup.html**

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <link rel="stylesheet" href="popup.css">
</head>
<body>
  <div id="app">
    <h1>Hoarder</h1>

    <div id="status-section">
      <p id="page-status">Checking page...</p>
      <button id="archive-btn" class="primary" disabled>Archive This</button>
    </div>

    <div id="manual-section">
      <input type="text" id="manual-url" placeholder="Paste any URL...">
      <button id="manual-submit">Submit</button>
    </div>

    <details id="settings-section">
      <summary>Settings</summary>
      <label>NAS URL
        <input type="text" id="nas-url" placeholder="http://newnas.local">
      </label>
      <label>TubeArchivist API Key
        <input type="password" id="ta-api-key" placeholder="Enter API key">
      </label>
      <label>
        <input type="checkbox" id="auto-detect"> Auto-detect supported pages
      </label>
      <button id="save-settings">Save</button>
      <p id="settings-status"></p>
    </details>
  </div>
  <script src="popup.js" type="module"></script>
</body>
</html>
```

**Step 2: Write popup.css**

```css
* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  width: 320px;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 14px;
  padding: 16px;
  color: #1a1a1a;
}

h1 {
  font-size: 18px;
  margin-bottom: 12px;
}

#status-section, #manual-section, #settings-section {
  margin-bottom: 12px;
}

#page-status {
  margin-bottom: 8px;
  color: #666;
}

button {
  padding: 8px 16px;
  border: 1px solid #ccc;
  border-radius: 4px;
  background: #fff;
  cursor: pointer;
  font-size: 13px;
}

button.primary {
  background: #4CAF50;
  color: white;
  border-color: #4CAF50;
  width: 100%;
}

button.primary:disabled {
  background: #ccc;
  border-color: #ccc;
  cursor: default;
}

#manual-section {
  display: flex;
  gap: 8px;
}

#manual-url {
  flex: 1;
  padding: 8px;
  border: 1px solid #ccc;
  border-radius: 4px;
  font-size: 13px;
}

details summary {
  cursor: pointer;
  color: #666;
  font-size: 13px;
}

details label {
  display: block;
  margin: 8px 0 4px;
  font-size: 12px;
  color: #666;
}

details input[type="text"],
details input[type="password"] {
  width: 100%;
  padding: 6px;
  border: 1px solid #ccc;
  border-radius: 4px;
  font-size: 13px;
  margin-top: 2px;
}

details label:has(input[type="checkbox"]) {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 8px;
}

#save-settings {
  margin-top: 8px;
  width: 100%;
}

#settings-status {
  margin-top: 4px;
  font-size: 12px;
  color: #4CAF50;
}
```

**Step 3: Write popup.js**

```javascript
import { getConfig, saveConfig, getTargetService } from "../config.js";
import { submitUrl } from "../api.js";

document.addEventListener("DOMContentLoaded", async () => {
  const config = await getConfig();
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

  document.getElementById("nas-url").value = config.nasBaseUrl;
  document.getElementById("ta-api-key").value = config.taApiKey;
  document.getElementById("auto-detect").checked = config.autoDetect;

  const pageStatus = document.getElementById("page-status");
  const archiveBtn = document.getElementById("archive-btn");

  if (tab?.url) {
    const hostname = new URL(tab.url).hostname;
    const isSupported = config.supportedDomains.some((d) => hostname.includes(d));
    if (isSupported) {
      const service = getTargetService(tab.url);
      pageStatus.textContent = `Archivable → ${service}`;
      archiveBtn.disabled = false;
    } else {
      pageStatus.textContent = "Not a supported page";
    }
  }

  archiveBtn.addEventListener("click", async () => {
    archiveBtn.disabled = true;
    archiveBtn.textContent = "Submitting...";
    const ok = await submitUrl(tab.url);
    archiveBtn.textContent = ok ? "Submitted!" : "Failed";
    setTimeout(() => window.close(), 1500);
  });

  document.getElementById("manual-submit").addEventListener("click", async () => {
    const url = document.getElementById("manual-url").value.trim();
    if (!url) return;
    const ok = await submitUrl(url);
    document.getElementById("manual-url").value = ok ? "Submitted!" : "Failed";
  });

  document.getElementById("save-settings").addEventListener("click", async () => {
    await saveConfig({
      nasBaseUrl: document.getElementById("nas-url").value.trim(),
      taApiKey: document.getElementById("ta-api-key").value.trim(),
      autoDetect: document.getElementById("auto-detect").checked,
    });
    document.getElementById("settings-status").textContent = "Saved!";
    setTimeout(() => {
      document.getElementById("settings-status").textContent = "";
    }, 2000);
  });
});
```

**Step 4: Commit**

```bash
git add src/popup/
git commit -m "feat: add popup UI with archive button, manual URL, and settings"
```

---

## Task 9: Integration Test — Full Extension Load

**Repo:** `/Volumes/dev/hoarder-extension`

**Step 1: Verify all tests pass**

Run: `cd /Volumes/dev/hoarder-extension && npx vitest run`
Expected: all tests PASS

**Step 2: Load extension in Chrome**

1. Open `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked" → select `/Volumes/dev/hoarder-extension`
4. Verify extension loads without errors
5. Check the popup opens and displays correctly
6. Right-click an image on any page → verify "Save to NAS" context menu appears

**Step 3: Load extension in Firefox**

1. Open `about:debugging#/runtime/this-firefox`
2. Click "Load Temporary Add-on" → select `manifest.json`
3. Verify extension loads without errors

**Step 4: Commit any fixes needed, then tag**

```bash
git tag v0.1.0
```

---

## Task 10: Deploy NAS Services

**Repo:** `/Volumes/dev/homelab`

**Step 1: Create data directories on NAS**

```bash
ssh newnas.local 'sudo mkdir -p /data/archive/{youtube,youtube-cache,media,images}'
```

**Step 2: Copy docker-compose and image-api to NAS**

```bash
scp -r apps/internet-archive/ newnas.local:~/internet-archive/
```

**Step 3: Start services**

```bash
ssh newnas.local 'cd ~/internet-archive && docker compose up -d'
```

**Step 4: Verify services are running**

```bash
ssh newnas.local 'docker compose -f ~/internet-archive/docker-compose.yml ps'
curl http://newnas.local:8082/health   # Image API
curl http://newnas.local:8081          # MeTube UI
curl http://newnas.local:8000          # TubeArchivist UI
```

**Step 5: Get TubeArchivist API key**

1. Open `http://newnas.local:8000` in browser
2. Log in with `tubearchivist` / the password you set
3. Go to Settings → copy API key
4. Paste into Hoarder extension settings

---

## Summary

| Task | What | Where |
|------|------|-------|
| 1 | Docker Compose for all NAS services | homelab repo |
| 2 | Image Archive API (FastAPI + SQLite) | homelab repo |
| 3 | Initialize extension repo + manifest | hoarder-extension |
| 4 | Cookie extraction + config modules | hoarder-extension |
| 5 | API submission module | hoarder-extension |
| 6 | Background service worker | hoarder-extension |
| 7 | Content script (metadata) | hoarder-extension |
| 8 | Popup UI | hoarder-extension |
| 9 | Integration test — load in browsers | hoarder-extension |
| 10 | Deploy NAS services | newnas.local |
