"""Buddy read-receipt tracker (Mailsuite-style).

GET /o/<id>.gif  -> records an open for <id>, returns a 1x1 transparent GIF (never cached).
GET /s?ids=a,b   -> opens per id, requires header x-buddy-key == KEY.
Records expire after 90 days (DynamoDB TTL). Stores only time + user agent; no email content.
"""
import base64
import json
import os
import time

import boto3

ddb = boto3.client("dynamodb")
TABLE = os.environ["TABLE"]
KEY = os.environ["KEY"]
GIF = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"


def _ok_id(i):
    return 16 <= len(i) <= 64 and i.isalnum()


def handler(event, _ctx):
    path = event.get("rawPath", "")
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    if path.startswith("/o/"):
        i = path[3:].split(".")[0]
        if _ok_id(i):
            now = int(time.time())
            try:
                ddb.update_item(
                    TableName=TABLE,
                    Key={"id": {"S": i}},
                    # keep at most ~50 opens per email
                    UpdateExpression="SET opens = list_append(if_not_exists(opens, :e), :o), expires = :x",
                    ConditionExpression="attribute_not_exists(opens) OR size(opens) < :max",
                    ExpressionAttributeValues={
                        ":e": {"L": []},
                        ":o": {"L": [{"M": {"t": {"N": str(now * 1000)}, "ua": {"S": headers.get("user-agent", "")[:200]}}}]},
                        ":x": {"N": str(now + 90 * 86400)},
                        ":max": {"N": "50"},
                    },
                )
            except ddb.exceptions.ConditionalCheckFailedException:
                pass
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "image/gif", "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0", "Pragma": "no-cache"},
            "body": GIF,
            "isBase64Encoded": True,
        }

    if path == "/s":
        if headers.get("x-buddy-key") != KEY:
            return {"statusCode": 403, "body": "forbidden"}
        q = event.get("queryStringParameters") or {}
        ids = [i for i in q.get("ids", "").split(",") if _ok_id(i)][:100]
        out = {}
        if ids:
            r = ddb.batch_get_item(RequestItems={TABLE: {"Keys": [{"id": {"S": i}} for i in ids]}})
            for it in r.get("Responses", {}).get(TABLE, []):
                out[it["id"]["S"]] = [
                    {"t": int(o["M"]["t"]["N"]), "ua": o["M"].get("ua", {}).get("S", "")} for o in it.get("opens", {}).get("L", [])
                ]
        return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps(out)}

    return {"statusCode": 404, "body": ""}
