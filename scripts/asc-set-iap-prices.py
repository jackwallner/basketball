#!/usr/bin/env python3
"""Set USD prices and the free trial for the StatScout+ products.

Base territory is USA; Apple's automatic equalization covers everything else.
PPP overrides are applied later by the fleet-wide pricing tooling in ~/ios/pricing.

Idempotent. Run after asc-setup-iap.py, and take the same optional product-id
arguments to work on part of the lineup:

    ./scripts/asc-set-iap-prices.py com.jackwallner.basketball.pro.monthly
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asc_iap_lib import ASC  # noqa: E402

APP_ID = "6820647074"
BASE_TERRITORY = "USA"
DRY_RUN = os.environ.get("DRY_RUN") == "1"

# Empty means every product below.
ONLY = set(sys.argv[1:])

# Same lineup as Football StatScout: monthly entry, yearly value, lifetime keeps.
SUB_PRICES = {
    "com.jackwallner.basketball.pro.monthly": "1.99",
    "com.jackwallner.basketball.pro.yearly": "9.99",
}
TRIALS = {
    "com.jackwallner.basketball.pro.monthly": "ONE_WEEK",
    "com.jackwallner.basketball.pro.yearly": "ONE_WEEK",
}
LIFETIME_PRICE = "19.99"
LIFETIME_PRODUCT = "com.jackwallner.basketball.pro"
V2 = "https://api.appstoreconnect.apple.com/v2"


def wanted(product_id: str) -> bool:
    return not ONLY or product_id in ONLY


def log(message: str) -> None:
    print(("[dry-run] " if DRY_RUN else "") + message)


def find_price_point(points: list[dict], target: str) -> dict | None:
    for point in points:
        if point["attributes"].get("customerPrice") == target:
            return point
    return None


def ensure_availability(asc: ASC, sub_id: str, product_id: str) -> None:
    """Make the subscription available in every territory.

    Prices cannot be attached before availability exists: ASC rejects the price
    point with a generic "problem processing the pricing information" 409.
    """
    existing = asc.get_optional(f"/subscriptions/{sub_id}/subscriptionAvailability")
    if existing.get("data"):
        log(f"  availability exists: {product_id}")
        return

    log(f"  setting availability (all territories): {product_id}")
    if DRY_RUN:
        return

    territories = [t["id"] for t in asc.get_all("/territories", limit=200)]
    asc.post(
        "/subscriptionAvailabilities",
        {
            "data": {
                "type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                    "availableTerritories": {
                        "data": [{"type": "territories", "id": t} for t in territories]
                    },
                },
            }
        },
    )


def set_subscription_prices(asc: ASC) -> None:
    groups = asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=20).get("data", [])
    for group in groups:
        subs = asc.get(f"/subscriptionGroups/{group['id']}/subscriptions", limit=20).get("data", [])
        for sub in subs:
            product_id = sub["attributes"].get("productId")
            target = SUB_PRICES.get(product_id)
            if not target or not wanted(product_id):
                continue

            ensure_availability(asc, sub["id"], product_id)

            existing = asc.get(f"/subscriptions/{sub['id']}/prices", limit=20).get("data", [])
            if existing:
                log(f"price already set: {product_id}")
                continue

            points = asc.get_all(
                f"/subscriptions/{sub['id']}/pricePoints",
                limit=200,
                **{"filter[territory]": BASE_TERRITORY},
            )
            point = find_price_point(points, target)
            if not point:
                available = sorted({p["attributes"].get("customerPrice") for p in points})[:12]
                raise SystemExit(f"No {target} price point for {product_id}. Nearby: {available}")

            log(f"setting {product_id} -> ${target}")
            if DRY_RUN:
                continue

            # No attributes and no territory relationship. Adding either makes ASC
            # 409 on the price point for a pre-launch subscription; the point ID
            # already encodes the territory.
            asc.post(
                "/subscriptionPrices",
                {
                    "data": {
                        "type": "subscriptionPrices",
                        "relationships": {
                            "subscription": {"data": {"type": "subscriptions", "id": sub["id"]}},
                            "subscriptionPricePoint": {
                                "data": {"type": "subscriptionPricePoints", "id": point["id"]}
                            },
                        },
                    }
                },
            )


def set_intro_offers(asc: ASC) -> None:
    """FREE_TRIAL on whichever subscriptions `TRIALS` names.

    The trial length is a deliberate bet, not the fleet default: see the SOSA
    benchmark note in AGENTS.md before changing it, and measure
    conversions / (conversions + expirations) rather than RC's headline.
    """
    groups = asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=20).get("data", [])
    for group in groups:
        subs = asc.get(f"/subscriptionGroups/{group['id']}/subscriptions", limit=20).get("data", [])
        for sub in subs:
            product_id = sub["attributes"].get("productId")
            duration = TRIALS.get(product_id)
            if not duration or not wanted(product_id):
                continue

            # Intro offers are per-territory, not global. One POST per territory.
            offers = asc.get_all(
                f"/subscriptions/{sub['id']}/introductoryOffers",
                limit=200,
                include="territory",
            )
            covered = set()
            for offer in offers:
                territory = (
                    (offer.get("relationships") or {}).get("territory", {}).get("data") or {}
                ).get("id")
                if territory:
                    covered.add(territory)

            territories = [t["id"] for t in asc.get_all("/territories", limit=200)]
            missing = [t for t in territories if t not in covered]
            if not missing:
                log(f"intro offer exists in all territories: {product_id}")
                continue

            log(f"creating {duration} free trial in {len(missing)} territories: {product_id}")
            if DRY_RUN:
                continue

            for territory in missing:
                asc.post(
                    "/subscriptionIntroductoryOffers",
                    {
                        "data": {
                            "type": "subscriptionIntroductoryOffers",
                            "attributes": {
                                "duration": duration,
                                "offerMode": "FREE_TRIAL",
                                "numberOfPeriods": 1,
                            },
                            "relationships": {
                                "subscription": {
                                    "data": {"type": "subscriptions", "id": sub["id"]}
                                },
                                "territory": {"data": {"type": "territories", "id": territory}},
                            },
                        }
                    },
                )


def ensure_iap_availability(asc: ASC, iap_id: str) -> None:
    """The IAP equivalent of `ensure_availability`.

    A priced, localized, screenshotted non-consumable still sits at
    MISSING_METADATA without this, and MISSING_METADATA products are never
    served to StoreKit.
    """
    existing = asc.get_optional(f"{V2}/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
    if existing.get("data"):
        log(f"  availability exists: {LIFETIME_PRODUCT}")
        return

    log(f"  setting availability (all territories): {LIFETIME_PRODUCT}")
    if DRY_RUN:
        return

    territories = [t["id"] for t in asc.get_all("/territories", limit=200)]
    asc.post(
        "/inAppPurchaseAvailabilities",
        {
            "data": {
                "type": "inAppPurchaseAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "availableTerritories": {
                        "data": [{"type": "territories", "id": t} for t in territories]
                    },
                },
            }
        },
    )


def set_lifetime_price(asc: ASC) -> None:
    if not wanted(LIFETIME_PRODUCT):
        return

    iaps = asc.get(f"/apps/{APP_ID}/inAppPurchasesV2", limit=20).get("data", [])
    iap = next((i for i in iaps if i["attributes"].get("productId") == LIFETIME_PRODUCT), None)
    if not iap:
        raise SystemExit(f"{LIFETIME_PRODUCT} not found; run asc-setup-iap.py first")

    ensure_iap_availability(asc, iap["id"])

    # ASC creates an empty schedule object with the product, so the schedule
    # existing says nothing. Only a manual price row means the price is set.
    schedule = asc.get_optional(f"{V2}/inAppPurchases/{iap['id']}/iapPriceSchedule")
    schedule_id = (schedule.get("data") or {}).get("id")
    if schedule_id:
        manual = asc.get_optional(f"/inAppPurchasePriceSchedules/{schedule_id}/manualPrices", limit=1)
        if manual.get("data"):
            log(f"price already set: {LIFETIME_PRODUCT}")
            return

    points = asc.get_all(
        f"{V2}/inAppPurchases/{iap['id']}/pricePoints",
        limit=200,
        **{"filter[territory]": BASE_TERRITORY},
    )
    point = find_price_point(points, LIFETIME_PRICE)
    if not point:
        available = sorted({p["attributes"].get("customerPrice") for p in points})[:12]
        raise SystemExit(f"No {LIFETIME_PRICE} price point. Nearby: {available}")

    log(f"setting {LIFETIME_PRODUCT} -> ${LIFETIME_PRICE}")
    if DRY_RUN:
        return

    asc.post(
        "/inAppPurchasePriceSchedules",
        {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap["id"]}},
                    "baseTerritory": {"data": {"type": "territories", "id": BASE_TERRITORY}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]},
                },
            },
            "included": [
                {
                    "type": "inAppPurchasePrices",
                    "id": "${price}",
                    "attributes": {"startDate": None},
                    "relationships": {
                        "inAppPurchasePricePoint": {
                            "data": {"type": "inAppPurchasePricePoints", "id": point["id"]}
                        }
                    },
                }
            ],
        },
    )


def main() -> None:
    asc = ASC()
    set_subscription_prices(asc)
    set_intro_offers(asc)
    set_lifetime_price(asc)
    print("\nDone.")


if __name__ == "__main__":
    main()
