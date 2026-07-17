from audio import build_ffmpeg_command, audio_output_path


def test_build_ffmpeg_command():
    cmd = build_ffmpeg_command("/data/video.mp4", "/data/video.mp3")
    assert cmd == [
        "ffmpeg", "-i", "/data/video.mp4",
        "-vn", "-acodec", "libmp3lame", "-q:a", "2",
        "-y", "/data/video.mp3",
    ]


def test_audio_output_path():
    assert audio_output_path("/data/media/Cool Video.mp4") == "/data/media/Cool Video.mp3"
    assert audio_output_path("/data/media/track.webm") == "/data/media/track.mp3"
