#!/usr/bin/python3
# SPDX-License-Identifier: MIT
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse

LOG = os.path.expanduser("~/.cache/recoll-launcher.log")
TAG = re.compile(r"<[^>]+>")
LINENO = re.compile(r"\[L\.\s*\d+\]")
paths = {}


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
    except OSError:
        pass


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


try:
    from recoll import recoll

    db = recoll.connect()
except Exception as e:
    log(f"fatal: cannot open Recoll index: {e}")
    sys.exit(1)


def search(text):
    paths.clear()
    term = text.strip()
    if term.lower().startswith("in:"):
        term = term[3:].strip()
    if len(term) >= 2:
        try:
            q = db.query()
            q.execute(term)
            for i, doc in enumerate(q.fetchmany(8)):
                abstract = db.makeDocAbstract(doc, q) or ""
                snippet = LINENO.sub("", TAG.sub("", abstract))
                snippet = re.sub(r"\s+", " ", snippet).strip()
                if len(snippet) > 120:
                    snippet = snippet[:117] + "..."
                url = doc.url
                if url.startswith("file://"):
                    url = urllib.parse.unquote(url[7:])
                paths[i] = url
                send(
                    {
                        "Append": {
                            "id": i,
                            "name": doc.filename or os.path.basename(url) or "Unnamed document",
                            "description": snippet,
                            "icon": {"Mime": doc.mimetype}
                            if doc.mimetype
                            else {"Name": "text-x-generic"},
                        }
                    }
                )
        except Exception as e:
            log(f"search error: {e}")
    send("Finished")


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
    except json.JSONDecodeError as e:
        log(f"bad json: {e}")
        continue
    if req == "Exit":
        break
    if isinstance(req, dict):
        if "Search" in req:
            search(req["Search"])
        elif "Activate" in req:
            p = paths.get(req["Activate"])
            if p:
                subprocess.Popen(
                    ["xdg-open", p],
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            send("Close")
