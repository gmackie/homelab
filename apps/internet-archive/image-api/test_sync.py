from sync import normalize_metube_item, normalize_ta_item, detect_platform, strip_query


def test_detect_platform():
    assert detect_platform("https://www.youtube.com/watch?v=abc") == "youtube"
    assert detect_platform("https://youtu.be/abc") == "youtube"
    assert detect_platform("https://soundcloud.com/artist/track") == "soundcloud"
    assert detect_platform("https://www.twitch.tv/user/clip/ClipId") == "twitch"
    assert detect_platform("https://example.com") == "other"


def test_strip_query():
    assert strip_query("https://example.com/path?a=1&b=2") == "https://example.com/path"
    assert strip_query("https://example.com/path") == "https://example.com/path"


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
    assert result["media_type"] == "video"
    assert result["id"] == "mt_123"


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
    assert result["audio_path"] == "/data/media/Cool Track.mp3"


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
    assert result["duration"] == 213
    assert result["url"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"


def test_normalize_ta_item_long_duration():
    item = {
        "youtube_id": "abc123",
        "title": "Long Video",
        "published": "2024-01-01",
        "channel": {"channel_name": "Channel"},
        "media_url": "/youtube/Channel/Long Video.mp4",
        "vid_thumb_url": "",
        "player": {"duration_str": "1:23:45"},
    }
    result = normalize_ta_item(item)
    assert result["duration"] == 5025
