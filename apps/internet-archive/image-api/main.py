import os
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8082)
