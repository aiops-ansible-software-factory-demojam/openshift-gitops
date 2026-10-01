"""Validate local manifest structure and select the demo's RHEL material.

This does not validate an AAP license, expiry, authenticity or CDN access.
Only AAP's manifest import can establish licensing acceptance.
"""
import io
import json
import zipfile


class ManifestError(RuntimeError):
    """A controlled message that never includes certificate/key contents."""


def read_rhel_entitlement(path):
    try:
        with zipfile.ZipFile(path) as outer:
            consumer = outer.read("consumer_export.zip")
        with zipfile.ZipFile(io.BytesIO(consumer)) as inner:
            entries = [json.loads(inner.read(info)) for info in inner.infolist()
                       if not info.is_dir() and info.filename.startswith("export/entitlements/")]
    except (OSError, KeyError, ValueError, zipfile.BadZipFile, RuntimeError):
        raise ManifestError("Manifest must be a readable ZIP containing consumer_export.zip and valid entitlement JSON") from None

    entitlement = None
    for entry in entries:
        try:
            pool = entry.get("pool", {})
            products = [pool.get("productName", "")] + [
                product.get("productName", "") for product in pool.get("providedProducts", [])]
            certificates = entry.get("certificates", [])
            if any(product in products for product in (
                    "Red Hat Enterprise Linux for x86_64", "Red Hat Enterprise Linux Server")):
                for certificate in certificates:
                    cert, key = certificate.get("cert"), certificate.get("key")
                    if all(isinstance(value, str) and value.strip() for value in (cert, key)):
                        entitlement = entitlement or cert + "\n" + key
        except (AttributeError, TypeError):
            raise ManifestError("Manifest entitlement JSON has an invalid structure") from None
    if entitlement is None:
        raise ManifestError("Manifest must include a RHEL entitlement with a nonempty certificate and private key")
    return entitlement
