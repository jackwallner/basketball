#!/usr/bin/env python3
"""Attach an App Review screenshot to a Baby Docs subscription or IAP.

A product without one sits at MISSING_METADATA forever, and a product at
MISSING_METADATA is never served to StoreKit, so the paywall renders its "no
prices came back" state on device even though the price and the trial are set.
That is the only reason this exists.

The picture has to be the app's own paywall. Generate it from StoreKit Testing
rather than by hand:

    UDID=$(agent-sim udid babydocs)
    xcodebuild test -project BabyDocs.xcodeproj -scheme BabyDocsUITests \
      -destination "id=$UDID" \
      -only-testing:BabyDocsUITests/ScreenshotUITests/testCaptureTheMainScreens \
      -derivedDataPath build/dd
    xcrun xcresulttool export attachments --path <the .xcresult> --output-path shots

then find `05-paywall` in `shots/manifest.json`.

    ./scripts/asc-upload-review-screenshot.py <productId> <path-to-png>
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asc_iap_lib import ASC  # noqa: E402

APP_ID = "6820647074"
V2 = "https://api.appstoreconnect.apple.com/v2"


def find_product(asc: ASC, product_id: str) -> tuple[str, str]:
    """Return (kind, id), where kind is 'subscriptions' or 'inAppPurchases'."""
    for group in asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=50).get("data", []):
        subs = asc.get(f"/subscriptionGroups/{group['id']}/subscriptions", limit=50)
        for sub in subs.get("data", []):
            if sub["attributes"].get("productId") == product_id:
                return "subscriptions", sub["id"]

    for iap in asc.get(f"/apps/{APP_ID}/inAppPurchasesV2", limit=50).get("data", []):
        if iap["attributes"].get("productId") == product_id:
            return "inAppPurchases", iap["id"]

    raise SystemExit(f"{product_id} not found on app {APP_ID}")


def existing_screenshot(asc: ASC, kind: str, product: str) -> dict:
    # The v1 IAP path answers 200 with an empty body for a screenshot that is
    # actually attached, so an upload run twice would silently upload twice.
    path = (
        f"/subscriptions/{product}/appStoreReviewScreenshot"
        if kind == "subscriptions"
        else f"{V2}/inAppPurchases/{product}/appStoreReviewScreenshot"
    )
    return asc.get_optional(path).get("data") or {}


def upload(asc: ASC, kind: str, product: str, image: Path) -> None:
    data = image.read_bytes()

    if kind == "subscriptions":
        collection = "/subscriptionAppStoreReviewScreenshots"
        resource = "subscriptionAppStoreReviewScreenshots"
        relationship = {"subscription": {"data": {"type": "subscriptions", "id": product}}}
    else:
        collection = "/inAppPurchaseAppStoreReviewScreenshots"
        resource = "inAppPurchaseAppStoreReviewScreenshots"
        relationship = {
            "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": product}}
        }

    reserved = asc.post(
        collection,
        {
            "data": {
                "type": resource,
                "attributes": {"fileSize": len(data), "fileName": image.name},
                "relationships": relationship,
            }
        },
    )
    asset_id = reserved["data"]["id"]

    # Apple hands back one or more pre-signed PUTs with byte ranges. Small files
    # come back as a single operation, but the loop is the documented contract.
    for operation in reserved["data"]["attributes"]["uploadOperations"]:
        chunk = data[operation["offset"] : operation["offset"] + operation["length"]]
        request = urllib.request.Request(
            operation["url"], data=chunk, method=operation["method"]
        )
        for header in operation.get("requestHeaders") or []:
            request.add_header(header["name"], header["value"])
        with urllib.request.urlopen(request) as response:
            response.read()

    asc.patch(
        f"{collection}/{asset_id}",
        {
            "data": {
                "type": resource,
                "id": asset_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(data).hexdigest(),
                },
            }
        },
    )
    print(f"uploaded {image.name} ({len(data)} bytes) as {asset_id}")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)

    product_id, path = sys.argv[1], Path(sys.argv[2])
    if not path.exists():
        raise SystemExit(f"No such file: {path}")

    asc = ASC()
    kind, product = find_product(asc, product_id)

    already = existing_screenshot(asc, kind, product)
    if already:
        print(f"screenshot already attached to {product_id}: {already['id']}")
        return

    upload(asc, kind, product, path)

    # /v1/inAppPurchases is the retired read-only collection and 404s on an id
    # created through v2; subscriptions still read off v1.
    path_for_state = (
        f"/subscriptions/{product}"
        if kind == "subscriptions"
        else f"{V2}/inAppPurchases/{product}"
    )
    state = asc.get(path_for_state)["data"]["attributes"].get("state")
    print(f"{product_id} state: {state}")
    print(json.dumps({"kind": kind, "id": product}, indent=1))


if __name__ == "__main__":
    main()
