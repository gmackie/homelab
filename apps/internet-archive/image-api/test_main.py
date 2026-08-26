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
async def test_destination_availability_uses_storedge_sentinel(
    client, tmp_path, monkeypatch
):
    sentinel = tmp_path / ".hoarder-storedge"
    monkeypatch.setenv("STOREDGE_SENTINEL_PATH", str(sentinel))

    unavailable = await client.get("/destinations")
    assert unavailable.status_code == 200
    assert unavailable.json() == {
        "destinations": [
            {"id": "newnas", "available": True},
            {"id": "storedge", "available": False},
        ]
    }

    sentinel.touch()
    available = await client.get("/destinations")
    assert available.json()["destinations"][1] == {
        "id": "storedge",
        "available": True,
    }

@pytest.mark.anyio
async def test_upload_image(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
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
    assert body["destination"] == "newnas"
    assert "id" in body


@pytest.mark.anyio
async def test_upload_image_to_storedge(client, tmp_path, monkeypatch):
    newnas_path = tmp_path / "newnas"
    storedge_path = tmp_path / "storedge"
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(newnas_path))
    monkeypatch.setenv("STOREDGE_IMAGE_STORAGE_PATH", str(storedge_path))
    sentinel = tmp_path / ".hoarder-storedge"
    sentinel.touch()
    monkeypatch.setenv("STOREDGE_SENTINEL_PATH", str(sentinel))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))

    resp = await client.post(
        "/upload",
        files={"image": ("storedge.png", io.BytesIO(b"storedge"), "image/png")},
        data={"destination": "storedge"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["destination"] == "storedge"
    assert not list(newnas_path.glob("*")) if newnas_path.exists() else True
    assert (storedge_path / f"{body['id']}.png").read_bytes() == b"storedge"


@pytest.mark.anyio
async def test_upload_to_storedge_fails_closed_without_mount_sentinel(
    client, tmp_path, monkeypatch
):
    storedge_path = tmp_path / "storedge"
    monkeypatch.setenv("STOREDGE_IMAGE_STORAGE_PATH", str(storedge_path))
    monkeypatch.setenv(
        "STOREDGE_SENTINEL_PATH", str(tmp_path / "missing-sentinel")
    )
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))

    resp = await client.post(
        "/upload",
        files={"image": ("unmounted.png", io.BytesIO(b"nope"), "image/png")},
        data={"destination": "storedge"},
    )

    assert resp.status_code == 503
    assert resp.json()["detail"] == "Storedge is not mounted"
    assert not storedge_path.exists()


@pytest.mark.anyio
async def test_upload_rejects_unknown_destination(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path / "newnas"))
    monkeypatch.setenv("STOREDGE_IMAGE_STORAGE_PATH", str(tmp_path / "storedge"))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))

    resp = await client.post(
        "/upload",
        files={"image": ("invalid.png", io.BytesIO(b"invalid"), "image/png")},
        data={"destination": "other"},
    )

    assert resp.status_code == 422
    assert not (tmp_path / "newnas").exists()
    assert not (tmp_path / "storedge").exists()

@pytest.mark.anyio
async def test_upload_image_no_tags(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
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
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
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
    assert items[0]["destination"] == "newnas"


def test_get_db_migrates_legacy_images_to_newnas(tmp_path, monkeypatch):
    db_path = tmp_path / "legacy.db"
    db = __import__("sqlite3").connect(db_path)
    db.execute(
        "CREATE TABLE images (id TEXT PRIMARY KEY, filename TEXT NOT NULL, "
        "source_url TEXT, page_title TEXT, tags TEXT, created_at TEXT NOT NULL)"
    )
    db.execute(
        "INSERT INTO images VALUES (?, ?, ?, ?, ?, ?)",
        ("legacy", "old.png", "", "", "", "2026-01-01"),
    )
    db.commit()
    db.close()
    monkeypatch.setenv("IMAGE_DB_PATH", str(db_path))

    from main import get_db
    migrated = get_db()
    row = migrated.execute(
        "SELECT destination FROM images WHERE id = ?", ("legacy",)
    ).fetchone()
    migrated.close()

    assert row["destination"] == "newnas"

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

@pytest.mark.anyio
async def test_set_channel_rule(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
    resp = await client.put("/channels/Rick%20Astley", json={"platform": "youtube", "mode": "audio_only"})
    assert resp.status_code == 200
    assert resp.json()["mode"] == "audio_only"
    resp = await client.get("/channels")
    rules = resp.json()
    assert len(rules) == 1
    assert rules[0]["channel"] == "Rick Astley"
    assert rules[0]["mode"] == "audio_only"

@pytest.mark.anyio
async def test_stream_not_found(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
    resp = await client.get("/stream/nonexistent")
    assert resp.status_code == 404

@pytest.mark.anyio
async def test_stream_media(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    db_path = str(tmp_path / "metadata.db")
    monkeypatch.setenv("IMAGE_DB_PATH", db_path)
    test_file = tmp_path / "test.mp4"
    test_file.write_bytes(b"fake video content")
    from main import get_db
    db = get_db()
    db.execute(
        "INSERT INTO media (id, source, media_type, title, url, platform, channel, "
        "thumbnail_path, file_path, audio_path, duration, file_size, tags, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("test1", "metube", "video", "Test", "http://example.com", "twitch",
         "", "", str(test_file), "", 0, 18, "", "2026-01-01"),
    )
    db.commit()
    db.close()
    resp = await client.get("/stream/test1")
    assert resp.status_code == 200
    assert b"fake video content" in resp.content

@pytest.mark.anyio
async def test_catalog_item_detail(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    db_path = str(tmp_path / "metadata.db")
    monkeypatch.setenv("IMAGE_DB_PATH", db_path)
    from main import get_db
    db = get_db()
    db.execute(
        "INSERT INTO media (id, source, media_type, title, url, platform, channel, "
        "thumbnail_path, file_path, audio_path, duration, file_size, tags, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("detail1", "tubearchivist", "video", "Detail Test", "http://yt.com/watch?v=x",
         "youtube", "Channel", "", "/data/vid.mp4", "", 120, 999, "", "2026-01-01"),
    )
    db.commit()
    db.close()
    resp = await client.get("/catalog/detail1")
    assert resp.status_code == 200
    body = resp.json()
    assert body["title"] == "Detail Test"
    assert body["channel"] == "Channel"

@pytest.mark.anyio
async def test_catalog_item_not_found(client, tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_STORAGE_PATH", str(tmp_path))
    monkeypatch.setenv("IMAGE_DB_PATH", str(tmp_path / "metadata.db"))
    resp = await client.get("/catalog/nope")
    assert resp.status_code == 404
