"""Lambda entry point: wires the DynamoDB store into the router once per container."""
import os

from routes import route
from store import DynamoOpensStore

_store = DynamoOpensStore(os.environ["TABLE"])
_key = os.environ["KEY"]


def handler(event, _ctx):
    return route(event, _store, _key)
