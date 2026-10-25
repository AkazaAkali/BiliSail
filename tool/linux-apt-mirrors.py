"""Prefer Ubuntu's primary archives over the hosted runner's Azure mirror."""

from pathlib import Path
import re
import sys


def prefer_ubuntu_archives(mirrorlist: str) -> str:
    priorities = {
        "https://archive.ubuntu.com/ubuntu": 1,
        "http://archive.ubuntu.com/ubuntu": 1,
        "https://security.ubuntu.com/ubuntu": 2,
        "http://security.ubuntu.com/ubuntu": 2,
        "http://azure.archive.ubuntu.com/ubuntu": 3,
        "https://azure.archive.ubuntu.com/ubuntu": 3,
    }
    lines = mirrorlist.splitlines(keepends=True)
    # Leave unrelated/custom installations alone, even if run by another CI.
    if not any(
        line.split("\t", 1)[0].rstrip("/\r\n")
        in ("http://azure.archive.ubuntu.com/ubuntu", "https://azure.archive.ubuntu.com/ubuntu")
        for line in lines
    ):
        return mirrorlist
    result = []
    for line in lines:
        uri = line.split("\t", 1)[0].rstrip("/\r\n")
        if uri in priorities:
            priority = f"priority:{priorities[uri]}"
            if re.search(r"\bpriority:\d+\b", line):
                line = re.sub(r"\bpriority:\d+\b", priority, line)
            else:
                line = line.rstrip("\r\n") + "\t" + priority + "\n"
        result.append(line)
    return "".join(result)


if __name__ == "__main__":
    path = Path(sys.argv[1])
    original = path.read_text(encoding="utf-8")
    updated = prefer_ubuntu_archives(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
