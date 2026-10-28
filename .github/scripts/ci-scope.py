#!/usr/bin/env python3
"""Scope CI to the source surfaces changed by a push or pull request."""
import os
from pathlib import Path
import subprocess


def scopes(paths):
    workflow = any(p.startswith(".github/scripts/") or p in (
        ".github/workflows/build.yml", ".github/workflows/codeql.yml"
    ) for p in paths)
    native = workflow or any(p.startswith(("PingWarden/", "scripts/")) or
                             p in ("Package.swift", "Package.resolved") for p in paths)
    site = workflow or any(p.startswith(("Site/", "scripts/")) for p in paths)
    shell = workflow or any(p.endswith(".sh") for p in paths)
    return {"native": native, "site": site, "shell": shell}


def main():
    base, head = os.environ.get("BASE_SHA", ""), os.environ.get("HEAD_SHA", "HEAD")
    if not base or set(base) == {"0"}:
        result = dict.fromkeys(("native", "site", "shell"), True)
    else:
        paths = subprocess.check_output(["git", "diff", "--name-only", base, head], text=True).splitlines()
        result = scopes(paths)
    output = "".join(f"{key}={str(value).lower()}\n" for key, value in result.items())
    print(output, end="")
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as stream:
        stream.write(output)


if __name__ == "__main__":
    main()
