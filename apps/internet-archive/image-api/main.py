import asyncio
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, Response
from fastapi.staticfiles import StaticFiles

from audio import extract_audio
from sync import run_sync


@asynccontextmanager
async def lifespan(app):
    async def sync_loop():
        while True:
            try:
                db = get_db()
                run_sync(db)
                db.close()
            except Exception as e:
                print(f"[sync] Error: {e}")
            await asyncio.sleep(300)
    task = asyncio.create_task(sync_loop())
    yield
    task.cancel()


app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

static_dir = Path(__file__).parent / "static"
if static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

def _db_path():
    return os.environ.get("IMAGE_DB_PATH", "/data/images/metadata.db")


def _storage_path():
    return os.environ.get("IMAGE_STORAGE_PATH", "/data/images/files")


def get_db():
    path = Path(_db_path())
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
    conn.commit()
    return conn


@app.get("/", response_class=HTMLResponse)
def index():
    return (Path(__file__).parent / "static" / "index.html").read_text()


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
    storage = Path(_storage_path())
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


@app.get("/catalog")
def list_catalog(tab: str = "video", q: str = "", platform: str = "", page: int = 1):
    db = get_db()
    page_size = 50
    offset = (page - 1) * page_size
    conditions = ["media_type = ?"]
    params: list = [tab]
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


@app.post("/catalog/sync")
def trigger_sync():
    db = get_db()
    count = run_sync(db)
    db.close()
    return {"status": "ok", "new_items": count}


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


@app.get("/catalog/{media_id}")
def get_catalog_item(media_id: str):
    db = get_db()
    row = db.execute("SELECT * FROM media WHERE id = ?", (media_id,)).fetchone()
    db.close()
    if not row:
        return Response(status_code=404)
    return dict(row)


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


@app.put("/channels/{channel}")
def set_channel_rule(channel: str, body: dict):
    db = get_db()
    db.execute(
        "INSERT INTO channel_rules (channel, platform, mode) VALUES (?, ?, ?) "
        "ON CONFLICT(channel) DO UPDATE SET mode = ?, platform = ?",
        (channel, body.get("platform", ""), body.get("mode", "video"),
         body.get("mode", "video"), body.get("platform", "")),
    )
    db.commit()
    db.close()
    return {"status": "ok", "channel": channel, "mode": body.get("mode", "video")}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8082)
