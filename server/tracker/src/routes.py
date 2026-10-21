"""Buddy read-receipt tracker (Mailsuite-style) HTTP layer.

GET /o/<id>.gif  -> records an open for <id>, returns a 1x1 transparent GIF (never cached).
GET /s?ids=a,b   -> opens per id, requires header x-buddy-key == key.
"""
import hmac
import json

from store import valid_id

GIF = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
MAX_IDS = 100


def route(event, store, key):
    path = event.get("rawPath", "")
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if path.startswith("/o/"):
        return _pixel(path[3:].split(".")[0], headers, store)
    if path == "/s":
        if not hmac.compare_digest(headers.get("x-buddy-key", "").encode(), key.encode()):
            return {"statusCode": 403, "body": "forbidden"}
        return _status((event.get("queryStringParameters") or {}).get("ids", ""), store)
    return {"statusCode": 404, "body": ""}


def _pixel(i, headers, store):
    if valid_id(i):
        store.record(i, headers.get("user-agent", "")[:200])
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "image/gif", "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0", "Pragma": "no-cache"},
        "body": GIF,
        "isBase64Encoded": True,
    }


def _status(raw, store):
    ids = [i for i in raw.split(",") if valid_id(i)][:MAX_IDS]
    out = store.opens(ids) if ids else {}
    return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps(out)}
