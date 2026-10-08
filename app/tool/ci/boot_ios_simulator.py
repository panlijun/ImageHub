"""Boot one installed iPhone simulator without downloading additional runtimes."""

import json
import os
from pathlib import Path
import subprocess


def version_key(runtime):
    suffix = runtime.rsplit(".iOS-", 1)[1]
    return tuple(int(part) for part in suffix.split("-") if part.isdigit())


def main():
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    devices = json.loads(result.stdout)["devices"]
    candidates = [
        (runtime, device)
        for runtime, group in devices.items()
        if ".iOS-" in runtime and version_key(runtime) >= (15,)
        for device in group
        if device.get("isAvailable") and device["name"].startswith("iPhone")
    ]
    if not candidates:
        raise SystemExit("No installed compatible iPhone simulator is available; no runtime was downloaded.")
    runtime, device = sorted(candidates, key=lambda item: (version_key(item[0]), item[1]["name"]))[-1]
    if device["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], check=True)
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
        output.write(f"IMAGEHOST_IOS_SIMULATOR={device['udid']}\n")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as output:
        output.write(f"iOS Simulator: {device['name']}, `{runtime}`. No physical-device evidence.\n")


if __name__ == "__main__":
    main()
