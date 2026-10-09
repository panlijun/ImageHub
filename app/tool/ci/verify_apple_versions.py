"""Check the built app's actual native versions against the independent manifest."""

import argparse
import json
from pathlib import Path
import plistlib


def verify(platform, app, versions):
    relative = "Contents/Info.plist" if platform == "macos" else "Info.plist"
    path = app / relative
    if app.is_symlink() or path.is_symlink() or not path.is_file():
        raise ValueError("The built application's ordinary native plist is required.")
    with path.open("rb") as stream:
        actual = plistlib.load(stream)
    own = versions["platforms"][platform]
    kernel = versions["kernel"]
    wanted = {
        "CFBundleShortVersionString": own["version"],
        "CFBundleVersion": str(own["build"]),
        "ImageHubKernelVersion": kernel["version"],
        "ImageHubKernelRevision": str(kernel["revision"]),
    }
    for field, value in wanted.items():
        if actual.get(field) != value:
            raise ValueError("The built native version does not match: " + field)
    if actual.get("CFBundleIdentifier") != "io.imagehost.imagehost":
        raise ValueError("The stable application identity changed.")
    return {"platform": platform, "verified": True, "native": wanted,
            "bundleIdentifier": actual["CFBundleIdentifier"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("macos", "ios"))
    parser.add_argument("app", type=Path)
    parser.add_argument("--versions", type=Path, default=Path("versions.json"))
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.platform, args.app,
                    json.loads(args.versions.read_text(encoding="utf-8")))
    args.summary.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
