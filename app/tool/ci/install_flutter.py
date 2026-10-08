"""Install the project's exact Flutter SDK on a disposable Apple CI runner."""

import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import urllib.request


def main():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("This workflow requires a standard Apple Silicon Mac runner.")

    project = Path(__file__).resolve().parents[2]
    version = None
    for line in (project / "pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if line.startswith("  flutter: '"):
            version = line.split("'", 2)[1].removeprefix(">=")
    if not version:
        raise SystemExit("The exact project Flutter baseline could not be read.")

    base_url = "https://storage.googleapis.com/flutter_infra_release/releases/"
    with urllib.request.urlopen(base_url + "releases_macos.json", timeout=60) as response:
        metadata = json.load(response)
    if metadata.get("base_url", "").rstrip("/") != base_url.rstrip("/"):
        raise SystemExit("Unexpected official archive origin.")
    matches = [
        release
        for release in metadata["releases"]
        if release["version"] == version
        and release["channel"] == "stable"
        and release.get("dart_sdk_arch") == "arm64"
    ]
    if len(matches) != 1:
        raise SystemExit("The official metadata must contain exactly one matching stable arm64 SDK.")
    release = matches[0]
    archive_name = release["archive"]
    expected_prefix = "stable/macos/flutter_macos_arm64_"
    if not archive_name.startswith(expected_prefix) or ".." in archive_name or not archive_name.endswith(".zip"):
        raise SystemExit("Unexpected official archive path.")
    digest = release["sha256"]
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise SystemExit("Unexpected official archive checksum.")

    destination = Path(os.environ["RUNNER_TEMP"]) / "imagehost-flutter"
    destination.mkdir(exist_ok=False)
    archive = destination / "sdk.zip"
    actual = hashlib.sha256()
    with urllib.request.urlopen(base_url + archive_name, timeout=60) as response, archive.open("xb") as output:
        while chunk := response.read(1024 * 1024):
            actual.update(chunk)
            output.write(chunk)
    if actual.hexdigest() != digest:
        raise SystemExit("The Flutter archive does not match its official SHA-256.")
    subprocess.run(["ditto", "-x", "-k", str(archive), str(destination)], check=True)
    archive.unlink()
    flutter = destination / "flutter" / "bin" / "flutter"
    subprocess.run([str(flutter), "config", "--no-analytics"], check=True)
    subprocess.run([str(flutter), "--version"], check=True)
    with Path(os.environ["GITHUB_PATH"]).open("a", encoding="utf-8") as output:
        output.write(str(flutter.parent) + "\n")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as output:
        output.write(f"Flutter {version}, macOS arm64, official archive SHA-256 `{digest}`.\n")


if __name__ == "__main__":
    main()
