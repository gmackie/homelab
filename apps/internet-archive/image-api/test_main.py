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
    assert "id" in body

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
