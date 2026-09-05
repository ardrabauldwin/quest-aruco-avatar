"""Copy and validate every CSV stored in the debug Quest application sandbox."""

from __future__ import annotations

import argparse
import csv
import io
from pathlib import Path
import subprocess


PACKAGE = "de.unigreifswald.opencvaruco"


def adb_bytes(adb: Path, *args: str) -> bytes:
    return subprocess.check_output([str(adb), *args])


def validate_csv(data: bytes) -> tuple[bool, int, str]:
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        return False, 0, f"not UTF-8: {error}"
    try:
        rows = list(csv.reader(io.StringIO(text)))
    except csv.Error as error:
        return False, 0, f"CSV parse error: {error}"
    if not rows:
        return False, 0, "empty file"
    if not rows[0] or not any(cell.strip() for cell in rows[0]):
        return False, max(0, len(rows) - 1), "missing header"
    width = len(rows[0])
    bad_rows = [index for index, row in enumerate(rows[1:], start=2) if len(row) != width]
    if bad_rows:
        preview = ", ".join(map(str, bad_rows[:5]))
        return False, len(rows) - 1, f"column-count mismatch at row(s) {preview}"
    if len(rows) == 1:
        return False, 0, "header only; no samples"
    return True, len(rows) - 1, "ok"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()

    listing = adb_bytes(
        args.adb,
        "shell",
        "run-as",
        PACKAGE,
        "find",
        "files",
        "-maxdepth",
        "1",
        "-type",
        "f",
    ).decode("utf-8", errors="replace")
    remote_files = sorted(line.strip() for line in listing.splitlines() if line.strip().endswith(".csv"))
    args.destination.mkdir(parents=True, exist_ok=False)

    good = 0
    bad = 0
    total_bytes = 0
    for remote in remote_files:
        name = Path(remote).name
        if name in {"", ".", ".."}:
            raise RuntimeError(f"unsafe remote name: {remote!r}")
        data = adb_bytes(args.adb, "exec-out", "run-as", PACKAGE, "cat", remote)
        (args.destination / name).write_bytes(data)
        total_bytes += len(data)
        valid, samples, reason = validate_csv(data)
        if valid:
            good += 1
        else:
            bad += 1
        status = "GOOD" if valid else "BAD "
        print(f"{status}  {name:42s} samples={samples:5d} bytes={len(data):8d}  {reason}")

    print(
        f"SUMMARY files={len(remote_files)} good={good} bad={bad} "
        f"bytes={total_bytes} destination={args.destination.resolve()}"
    )


if __name__ == "__main__":
    main()
