#!/usr/bin/env python3
"""Run the Showdown Clone headless test suite under LuaJIT (via lupa).

The engine (Core/) is plain Lua 5.1 with no WoW dependencies, so we can
execute it directly. Usage:

    python3 tests/run_tests.py
"""
import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST = os.path.join(ROOT, "tests", "run_tests.lua")


def main() -> int:
    lua = LuaRuntime(unpack_returned_tuples=True)
    # make `arg` and package.path behave like the standalone runner
    lua.execute(
        """
        _LUPA = true
        arg = { [0] = "tests/run_tests.lua" }
        package.path = "?.lua;?/init.lua;" .. package.path
        """
    )
    # run from the repo root so relative requires work
    os.chdir(ROOT)
    try:
        lua.execute(f'dofile("{TEST}")')
    except Exception as exc:  # noqa: BLE001
        print(f"Lua error: {exc}")
        return 1
    result = lua.globals()._TEST_RESULT
    if result is None:
        print("Test runner did not produce a result table")
        return 1
    return 1 if result["failed"] > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
