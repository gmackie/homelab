import subprocess
from pathlib import Path


def audio_output_path(video_path):
    return str(Path(video_path).with_suffix(".mp3"))


def build_ffmpeg_command(input_path, output_path):
    return [
        "ffmpeg", "-i", input_path,
        "-vn", "-acodec", "libmp3lame", "-q:a", "2",
        "-y", output_path,
    ]


def extract_audio(video_path):
    output = audio_output_path(video_path)
    cmd = build_ffmpeg_command(video_path, output)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {result.stderr}")
    return output
