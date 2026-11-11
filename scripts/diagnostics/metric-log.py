#!/usr/bin/env python3
"""Read plain or gzip-compressed numerical diagnostic logs."""

import gzip
from pathlib import Path


def read_text(path):
    """Return UTF-8 log text, transparently accepting a .log.gz fixture."""
    path = Path(path)
    if path.suffix == ".gz":
        with gzip.open(path, "rt", encoding="utf-8") as stream:
            return stream.read()
    return path.read_text(encoding="utf-8")
