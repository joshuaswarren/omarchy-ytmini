#!/usr/bin/env python3
"""Add the 'Fling to YT Mini' bookmarklet to a Chromium-family browser.

Usage:
  add-browser-bookmark.py <path-to-Bookmarks-file> [--dry]

The browser MUST be closed while this runs (it rewrites the Bookmarks file
from memory on exit and would clobber the edit). Idempotent: re-running
does nothing if the bookmarklet is already present.
"""
import datetime
import json
import os
import shutil
import sys
import tempfile
import uuid

NAME = "▶ Fling to YT Mini"
URL = "javascript:location.href='ytmini://throw?url='+encodeURIComponent(location.href)"


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--dry"]
    dry = "--dry" in sys.argv
    if not args:
        print(__doc__)
        return 2
    path = os.path.expanduser(args[0])

    data = json.load(open(path))
    bar = data["roots"]["bookmark_bar"]
    if any(c.get("url") == URL for c in bar["children"]):
        print("already present, nothing to do")
        return 0

    def max_id(nodes, m=0):
        for n in nodes:
            m = max(m, int(n.get("id", 0)))
            m = max(m, max_id(n.get("children", []), m))
        return m

    node = {
        "date_added": str(int((datetime.datetime.now().timestamp() + 11644473600) * 1e6)),
        "guid": str(uuid.uuid4()),
        "id": str(max_id(list(data["roots"].values())) + 1),
        "name": NAME,
        "type": "url",
        "url": URL,
    }
    bar["children"].append(node)

    if dry:
        print(f"DRY OK — would append {NAME!r} as id {node['id']}")
        return 0
    tmp = tempfile.NamedTemporaryFile("w", dir=os.path.dirname(path), delete=False)
    tmp.write(json.dumps(data, indent=3))
    tmp.close()
    shutil.copystat(path, tmp.name)
    os.replace(tmp.name, path)
    print(f"WRITTEN — {NAME} as id {node['id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
