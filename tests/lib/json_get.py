#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Print one value from a JSON document: json_get.py '<json>' key [key ...]."""

import json
import sys


def main():
    document = json.loads(sys.argv[1])
    for key in sys.argv[2:]:
        document = document[key]
    print(json.dumps(document) if isinstance(document, dict | list) else document)


main()
