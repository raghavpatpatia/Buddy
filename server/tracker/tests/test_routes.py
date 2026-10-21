import os
import sys
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from routes import route  # noqa: E402
from store import MAX_OPENS  # noqa: E402

class MemoryOpensStore:
    def __init__(self):
        self.data = {}

    def record(self, i, ua):
        log = self.data.setdefault(i, [])
        if len(log) < MAX_OPENS:
            log.append({"t": int(time.time() * 1000), "ua": ua})

    def opens(self, ids):
        return {i: self.data[i] for i in ids if i in self.data}


KEY = "k" * 40
ID = "a" * 24


def get(path, headers=None, ids=None):
    e = {"rawPath": path, "headers": headers or {}}
    if ids is not None:
        e["queryStringParameters"] = {"ids": ids}
    return e


class RoutesTest(unittest.TestCase):
    def setUp(self):
        self.store = MemoryOpensStore()

    def test_pixel_records_open_and_is_uncached(self):
        r = route(get(f"/o/{ID}.gif", {"User-Agent": "Gmail"}), self.store, KEY)
        self.assertEqual(r["headers"]["Content-Type"], "image/gif")
        self.assertIn("no-store", r["headers"]["Cache-Control"])
        self.assertEqual(self.store.data[ID][0]["ua"], "Gmail")

    def test_bad_id_still_returns_pixel_but_records_nothing(self):
        for bad in ["short", "x" * 65, "a" * 20 + "-..", ""]:
            r = route(get(f"/o/{bad}.gif"), self.store, KEY)
            self.assertEqual(r["statusCode"], 200)
        self.assertEqual(self.store.data, {})

    def test_opens_are_capped(self):
        for _ in range(MAX_OPENS + 5):
            route(get(f"/o/{ID}.gif"), self.store, KEY)
        self.assertEqual(len(self.store.data[ID]), MAX_OPENS)

    def test_status_needs_key(self):
        self.assertEqual(route(get("/s", ids=ID), self.store, KEY)["statusCode"], 403)
        self.assertEqual(route(get("/s", {"x-buddy-key": "wrong"}, ids=ID), self.store, KEY)["statusCode"], 403)

    def test_status_returns_only_valid_known_ids(self):
        route(get(f"/o/{ID}.gif"), self.store, KEY)
        r = route(get("/s", {"X-Buddy-Key": KEY}, ids=f"{ID},bad,{'b' * 24}"), self.store, KEY)
        self.assertEqual(r["statusCode"], 200)
        self.assertIn(ID, r["body"])
        self.assertNotIn("b" * 24, r["body"])

    def test_unknown_path_is_404(self):
        self.assertEqual(route(get("/"), self.store, KEY)["statusCode"], 404)


if __name__ == "__main__":
    unittest.main()
