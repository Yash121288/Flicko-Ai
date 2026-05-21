from __future__ import annotations

from pathlib import PurePosixPath
from urllib.request import urlopen

from cloudinary import api as cloudinary_api
from cloudinary import uploader, utils
from django.conf import settings
from django.core.files.base import ContentFile, File
from django.core.files.storage import Storage
from django.utils.text import get_valid_filename


class CloudinaryRawMediaStorage(Storage):
    """
    Production media storage for generated reports and uploads.

    Uses Cloudinary raw assets so PDFs and HTML files are preserved as files,
    not reinterpreted as images. URLs are signed when delivery type is not
    public upload.
    """

    resource_type = "raw"

    def __init__(self) -> None:
        self.delivery_type = getattr(settings, "CLOUDINARY_DELIVERY_TYPE", "authenticated")
        self.media_prefix = getattr(settings, "CLOUDINARY_MEDIA_PREFIX", "flicko")
        self.invalidate = bool(getattr(settings, "CLOUDINARY_INVALIDATE", True))

    def _open(self, name: str, mode: str = "rb") -> File:
        with urlopen(self.url(name)) as response:  # nosec B310 - signed/media URL from trusted storage backend
            payload = response.read()
        return File(ContentFile(payload), name=name)

    def _save(self, name: str, content) -> str:
        final_name = self.get_available_name(name)
        public_id = self._public_id(final_name)
        if hasattr(content, "seek"):
            content.seek(0)
        upload_result = uploader.upload(
            content,
            resource_type=self.resource_type,
            public_id=public_id,
            type=self.delivery_type,
            unique_filename=False,
            overwrite=False,
            invalidate=self.invalidate,
            use_filename=False,
        )
        return str(upload_result.get("public_id") or public_id)

    def delete(self, name: str) -> None:
        if not name:
            return
        uploader.destroy(
            self._public_id(name),
            resource_type=self.resource_type,
            type=self.delivery_type,
            invalidate=self.invalidate,
        )

    def exists(self, name: str) -> bool:
        if not name:
            return False
        try:
            cloudinary_api.resource(
                self._public_id(name),
                resource_type=self.resource_type,
                type=self.delivery_type,
            )
            return True
        except Exception:
            return False

    def size(self, name: str) -> int:
        resource = cloudinary_api.resource(
            self._public_id(name),
            resource_type=self.resource_type,
            type=self.delivery_type,
        )
        return int(resource.get("bytes") or 0)

    def url(self, name: str) -> str:
        secure_url, _ = utils.cloudinary_url(
            self._public_id(name),
            resource_type=self.resource_type,
            type=self.delivery_type,
            secure=True,
            sign_url=self.delivery_type != "upload",
        )
        return secure_url

    def path(self, name: str) -> str:
        raise NotImplementedError("Cloudinary storage does not expose local filesystem paths.")

    def get_valid_name(self, name: str) -> str:
        path = PurePosixPath(str(name).replace("\\", "/").lstrip("/"))
        parts = [get_valid_filename(part) for part in path.parts if part not in {"", ".", ".."}]
        return "/".join(parts)

    def _public_id(self, name: str) -> str:
        cleaned = self.get_valid_name(name)
        prefix = str(self.media_prefix or "").strip().strip("/")
        if not prefix:
            return cleaned
        if cleaned.startswith(f"{prefix}/"):
            return cleaned
        return f"{prefix}/{cleaned}"
