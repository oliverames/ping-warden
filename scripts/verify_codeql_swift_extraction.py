#!/usr/bin/env python3
"""Require successful CodeQL extraction of every app and widget Swift source."""

import argparse
import csv
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def verify(extraction_csv: Path, repository: Path) -> None:
    repository = repository.resolve(strict=True)
    expected = set()
    for relative in ("PingWarden/PingWarden", "PingWarden/PingWardenWidget"):
        source_root = repository / relative
        if not source_root.is_dir():
            raise ValueError(f"Missing source directory: {relative}")
        sources = {path.relative_to(repository).as_posix() for path in source_root.rglob("*.swift")}
        if not sources:
            raise ValueError(f"No Swift sources found: {relative}")
        expected.update(sources)
    extracted = set()
    with extraction_csv.open(newline="") as stream:
        for row in csv.reader(stream, strict=True):
            if len(row) != 1 or not row[0]:
                raise ValueError("Malformed successful-extraction CSV row")
            extracted.add(row[0])
    missing = sorted(expected - extracted)
    if missing:
        raise ValueError("CodeQL did not successfully extract these Swift sources:\n" + "\n".join(missing))
    print(f"CodeQL successfully extracted all {len(expected)} application and widget Swift files.")



def bundled_library_paths(codeql: Path, distribution: Path, query: Path) -> list[str]:
    # Resolve only this query's dependencies through the bundle manifest. The
    # flat qlpacks inventory also includes embedded copies used by other packs.
    resolved = json.loads(subprocess.check_output([
        str(codeql), "resolve", "library-paths",
        "--additional-packs=" + str(distribution),
        "--common-caches=" + str(query.parent / "cache"), "--", str(query)
    ], text=True))
    if not isinstance(resolved, dict) or set(resolved) != {str(query)}:
        raise ValueError("CodeQL query library resolution is malformed")
    details = resolved[str(query)]
    if not isinstance(details, dict):
        raise ValueError("CodeQL query library resolution is malformed")
    paths = details.get("libraryPath")
    if not isinstance(paths, list) or not all(isinstance(path, str) for path in paths):
        raise ValueError("CodeQL query library paths are malformed")
    libraries = set()
    for path in paths:
        candidate = Path(path).resolve(strict=True)
        if candidate == query.parent.resolve(strict=True):
            continue
        if not candidate.is_relative_to(distribution) or not candidate.is_dir():
            raise ValueError(f"CodeQL query library is outside the bundle: {candidate}")
        libraries.add(str(candidate))
    scheme_value = details.get("dbscheme")
    if not isinstance(scheme_value, str):
        raise ValueError("CodeQL query has no Swift database schema")
    scheme = Path(scheme_value).resolve(strict=True)
    if (not scheme.is_file() or scheme.name != "swift.dbscheme"
            or str(scheme.parent) not in libraries):
        raise ValueError("CodeQL query does not resolve the bundled Swift database schema")
    return sorted(libraries)


def successful_files_csv(database: Path, scratch: Path) -> Path:
    distribution_value = os.environ.get("CODEQL_DIST")
    if not distribution_value:
        raise ValueError("CODEQL_DIST is not set by the CodeQL action")
    distribution = Path(distribution_value).resolve(strict=True)
    codeql = distribution / "codeql"
    (scratch / "qlpack.yml").write_text(
        "name: pingwarden/extraction-coverage\n"
        "version: 0.0.0\n"
        "dependencies:\n"
        "  codeql/swift-all: '*'\n"
    )
    query = scratch / "SuccessfulSwiftFiles.ql"
    query.write_text(
        "import swift\n\n"
        "from File file\n"
        "where file.isSuccessfullyExtracted() and exists(file.getRelativePath())\n"
        "select file.getRelativePath()\n"
    )
    libraries = bundled_library_paths(codeql, distribution, query)
    result = scratch / "successful-swift-files.bqrs"
    subprocess.run([
        str(codeql), "query", "run", "--database=" + str(database.resolve(strict=True)),
        "--additional-packs=" + os.pathsep.join(libraries),
        "--common-caches=" + str(scratch / "cache"),
        "--output=" + str(result), "--", str(query)
    ], check=True)
    decoded = scratch / "successful-swift-files.csv"
    subprocess.run([
        str(codeql), "bqrs", "decode", "--format=csv", "--no-titles",
        "--result-set=#select", "--common-caches=" + str(scratch / "cache"),
        "--output=" + str(decoded), "--", str(result)
    ], check=True)
    return decoded


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("repository", type=Path)
    args = parser.parse_args()
    try:
        with tempfile.TemporaryDirectory(
            prefix="pingwarden-codeql-coverage-", dir=os.environ.get("RUNNER_TEMP")
        ) as temporary:
            extracted = successful_files_csv(args.database, Path(temporary))
            verify(extracted, args.repository)
    except (OSError, ValueError, csv.Error, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
