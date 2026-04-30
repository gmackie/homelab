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
