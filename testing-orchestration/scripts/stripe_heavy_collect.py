#!/usr/bin/env python3
"""List unique class-level nodeids matching given pytest args.

pytest 9 changed the default `--collect-only -q` output from flat nodeids
(`path::Class::test`) to a tree format (`<Class XXX>`), breaking the simple
`grep '::'` approach used by `stripe_heavy_runner.sh`. This helper uses the
pytest programmatic API to iterate collected items and print one
`path::Class` per line, ready to be fed back to pytest for per-class
isolated invocations.

Usage:
    python stripe_heavy_collect.py <pytest-args>

Example:
    python stripe_heavy_collect.py tests/test_stripe/ -m stripe_heavy
"""

import io
import os
import sys
from contextlib import redirect_stdout, redirect_stderr

import pytest


class _Collector:
    def __init__(self):
        self.classes = set()

    # pytest_collection_finish runs AFTER all `pytest_collection_modifyitems`
    # hooks (including the built-in `-m` marker filter), so `session.items`
    # here reflects only the selected tests.
    def pytest_collection_finish(self, session):
        for item in session.items:
            parts = item.nodeid.split("::")
            if len(parts) >= 2:
                self.classes.add("::".join(parts[:2]))


def main():
    args = sys.argv[1:]
    plugin = _Collector()
    with open(os.devnull, "w") as devnull:
        with redirect_stdout(devnull), redirect_stderr(devnull):
            rc = pytest.main([*args, "--collect-only", "-q"], plugins=[plugin])
    for c in sorted(plugin.classes):
        print(c)
    sys.exit(0 if rc in (0, 5) else int(rc))


if __name__ == "__main__":
    main()
