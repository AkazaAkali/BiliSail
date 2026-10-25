"""Check staged Linux dependencies and retain their distro license metadata."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def run(*arguments: str, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        arguments, check=True, capture_output=True, text=True, env=env
    )
    return result.stdout


def main() -> None:
    appdir = Path(sys.argv[1]).resolve()
    version = sys.argv[2]
    libraries = sorted(path for path in appdir.rglob("*.so*") if path.is_file())
    if not any(path.name == "libmpv.so.2" for path in libraries):
        raise RuntimeError("The package must include dlopen'ed libmpv.so.2")
    env = dict(os.environ, LC_ALL="C")
    env["LD_LIBRARY_PATH"] = f"{appdir}/usr/bin/lib:{appdir}/usr/lib"
    for binary in [appdir / "usr/bin/bilisail", *libraries]:
        with binary.open("rb") as stream:
            magic = stream.read(4)
        if magic != b"\x7fELF":
            continue
        dependencies = run("ldd", str(binary), env=env)
        if "not found" in dependencies:
            raise RuntimeError(f"Unresolved dependencies: {binary}\n{dependencies}")

    # Bundled libraries keep their SONAMEs. Resolve ownership against the host's
    # package database, then retain versioned source-package names for rebuilding.
    patterns = sorted({f"*/{path.name}" for path in libraries})
    ownership = subprocess.run(
        ["dpkg-query", "--search", *patterns],
        capture_output=True, text=True, check=False,
    )
    if ownership.returncode not in (0, 1):
        raise RuntimeError(ownership.stderr)
    packages = sorted({
        line.split(": ", 1)[0]
        for line in ownership.stdout.splitlines()
        if ": /" in line
    })
    if not packages:
        raise RuntimeError("No distro dependency license metadata found")
    records = run(
        "dpkg-query", "--show",
        "--showformat=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n",
        *packages,
    )
    notices = appdir / "usr/share/doc/bilisail/dependencies"
    notices.mkdir(parents=True, exist_ok=True)
    for package in packages:
        copyright_file = Path("/usr/share/doc") / package.split(":")[0] / "copyright"
        if not copyright_file.is_file():
            raise RuntimeError(f"Distro license text missing: {package}")
        shutil.copyfile(copyright_file, notices / f"{package}.copyright")
    (notices / "packages.tsv").write_text(
        "binary\tversion\tsource\tsource-version\n" + records, encoding="utf-8"
    )
    (notices / "README.txt").write_text(
        "Ubuntu 24.04 dependency binaries. License texts are in *.copyright.\n"
        "packages.tsv records exact binary and source versions. Enable Ubuntu\n"
        "deb-src repositories, then fetch with: apt-get source SOURCE=VERSION\n"
        "Flutter, media-kit and the isolated bili_mux have separate notices.\n",
        encoding="utf-8",
    )
    # Flutter/Linux stores application version data here; reject stale bundles.
    version_file = appdir / "usr/bin/data/flutter_assets/version.json"
    metadata = json.loads(version_file.read_text(encoding="utf-8"))
    name, number = version.split("+")
    if metadata["version"] != name or metadata["build_number"] != number:
        raise RuntimeError(f"Linux version metadata mismatch: {metadata}")


if __name__ == "__main__":
    main()
