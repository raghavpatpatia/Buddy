"""Opens storage in DynamoDB. Stores only time + user agent."""
import time

MAX_OPENS = 50
TTL_DAYS = 90


def valid_id(i):
    return 16 <= len(i) <= 64 and i.isalnum()


class DynamoOpensStore:
    def __init__(self, table):
        import boto3  # only available inside Lambda

        self._ddb = boto3.client("dynamodb")
        self._table = table

    def record(self, i, ua):
        now = int(time.time())
        try:
            self._ddb.update_item(
                TableName=self._table,
                Key={"id": {"S": i}},
                UpdateExpression="SET opens = list_append(if_not_exists(opens, :e), :o), expires = :x",
                ConditionExpression="attribute_not_exists(opens) OR size(opens) < :max",
                ExpressionAttributeValues={
                    ":e": {"L": []},
                    ":o": {"L": [{"M": {"t": {"N": str(now * 1000)}, "ua": {"S": ua}}}]},
                    ":x": {"N": str(now + TTL_DAYS * 86400)},
                    ":max": {"N": str(MAX_OPENS)},
                },
            )
        except self._ddb.exceptions.ConditionalCheckFailedException:
            pass

    def opens(self, ids):
        r = self._ddb.batch_get_item(RequestItems={self._table: {"Keys": [{"id": {"S": i}} for i in ids]}})
        return {
            it["id"]["S"]: [{"t": int(o["M"]["t"]["N"]), "ua": o["M"].get("ua", {}).get("S", "")} for o in it.get("opens", {}).get("L", [])]
            for it in r.get("Responses", {}).get(self._table, [])
        }

