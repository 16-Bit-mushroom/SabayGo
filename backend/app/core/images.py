"""Image uploads: the type is read from the bytes, never from the
client's content type."""

from __future__ import annotations


def sniff_image_ext(data: bytes) -> str | None:
    """'jpg', 'png' or 'webp', or None for anything else."""
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None
