#!/usr/bin/env python3
"""Configure, validate and archive Ember. No credentials, uploads or publishing."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
RELEASE = ROOT / "Release"
RECEIPT = RELEASE / "validation.json"


def run(args, **kwargs):
    print("Running: " + " ".join(str(arg) for arg in args), flush=True)
    return subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, **kwargs)


def require_macos():
    if sys.platform != "darwin" or not shutil.which("xcodebuild"):
        raise SystemExit("This step requires macOS with Xcode. No iOS validation or archive was produced.")
    version = run(["xcodebuild", "-version"], capture_output=True, text=True).stdout
    match = re.search(r"Xcode (\d+)", version)
    if not match or int(match.group(1)) < 26:
        raise SystemExit("App Store submissions require Xcode 26 or later. Select the current release in xcode-select.")
    return version.strip()


def fingerprint():
    digest = hashlib.sha256()
    candidates = []
    for folder in ["Ember", "EmberTests", "EmberUITests", "Ember.xcodeproj"]:
        candidates.extend(path for path in (ROOT / folder).rglob("*") if path.is_file() and "xcuserdata" not in path.parts)
    candidates.extend([ROOT / "Config.xcconfig", ROOT / "Package.swift"])
    for path in sorted(candidates):
        digest.update(str(path.relative_to(ROOT)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def static_checks():
    info = plistlib.loads((ROOT / "Ember/Resources/Info.plist").read_bytes())
    privacy = plistlib.loads((ROOT / "Ember/Resources/PrivacyInfo.xcprivacy").read_bytes())
    assert info["CFBundleDisplayName"] == "Ember"
    assert "NSAllowsArbitraryLoads" not in str(info), "Do not disable transport security globally."
    assert privacy["NSPrivacyTracking"] is False
    assert any(x["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults" and "CA92.1" in x["NSPrivacyAccessedAPITypeReasons"] for x in privacy["NSPrivacyAccessedAPITypes"])
    import struct
    for path in (ROOT / "Ember/Resources/Assets.xcassets").rglob("Contents.json"):
        data = json.loads(path.read_text())
        for entry in data.get("images", []):
            image_path = path.parent / entry["filename"]
            image = image_path.read_bytes()
            assert image[:8] == b"\x89PNG\r\n\x1a\n"
            width, height = struct.unpack(">II", image[16:24])
            assert (width, height) == (1024, 1024)
            assert image[25] == 2, "App icons must be opaque RGB."
    assert (ROOT / "Ember.xcodeproj/xcshareddata/xcschemes/Ember.xcscheme").is_file()
    if sys.platform == "darwin":
        run(["plutil", "-lint", ROOT / "Ember.xcodeproj/project.pbxproj", ROOT / "Ember/Resources/Info.plist", ROOT / "Ember/Resources/PrivacyInfo.xcprivacy"])
    print("Static project, manifest and asset checks passed.")


def configure(args):
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}", args.bundle_id) or "example" in args.bundle_id.lower() or "YOUR" in args.bundle_id:
        raise SystemExit("Use a real, unique reverse-DNS bundle ID.")
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        raise SystemExit("The Apple Developer team ID must contain 10 uppercase letters/digits.")
    for value in [args.support_url, args.privacy_url]:
        parsed = urlparse(value)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or any(x in value for x in ["\n", "\r", "$", "example.com", "YOUR_"]):
            raise SystemExit("Use an HTTPS support/privacy URL you operate.")
    if not re.fullmatch(r"[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+", args.support_email):
        raise SystemExit("Provide a valid support email address.")
    if not args.publisher.strip() or any(c in args.publisher for c in "\n\r"):
        raise SystemExit("Provide your publisher name.")
    values = {"bundle_id": args.bundle_id, "team": args.team, "support_url": args.support_url, "privacy_url": args.privacy_url, "support_email": args.support_email, "publisher": args.publisher}
    config = "// Configured by scripts/release.py. Do not put signing secrets here.\n"
    config += f"EMBER_BUNDLE_ID = {args.bundle_id}\nDEVELOPMENT_TEAM = {args.team}\n"
    config += "EMBER_SUPPORT_URL = " + args.support_url.replace("https://", "https:/$()/", 1) + "\n"
    (ROOT / "Config.xcconfig").write_text(config)
    (RELEASE / "release-config.json").write_text(json.dumps(values, indent=2) + "\n")
    output = RELEASE / "Web"
    output.mkdir(exist_ok=True)
    for name in ["privacy", "support"]:
        template = (RELEASE / "Templates" / (name + ".html")).read_text()
        for key, value in values.items():
            template = template.replace("{{" + key + "}}", html.escape(value, quote=True))
        template = template.replace("{{date}}", datetime.now(timezone.utc).date().isoformat())
        (output / (name + ".html")).write_text(template)
    print("Configuration and support/privacy pages are ready. Host the pages at the specified URLs, then run validate.")


def choose_devices(iphone=None, ipad=None):
    data = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"], capture_output=True, text=True).stdout)
    devices = [(runtime, device) for runtime, entries in data["devices"].items() for device in entries if device.get("isAvailable") and "iOS" in runtime]
    def runtime_key(pair):
        return tuple(int(v) for v in re.findall(r"\d+", pair[0]))
    devices.sort(key=runtime_key, reverse=True)
    def choose(kind, supplied):
        matches = [device for _, device in devices if (device["udid"] == supplied if supplied else kind in device["name"])]
        if not matches:
            raise SystemExit(f"Install an available {kind} simulator runtime in Xcode, or pass its UDID.")
        return matches[0]
    return choose("iPhone", iphone), choose("iPad", ipad)


def validate(args):
    static_checks()
    if args.core_only:
        run(["swift", "test", "-j", "1"])
        print("Portable core passed. iOS remains unverified; no release receipt was written.")
        return
    version = require_macos()
    if RECEIPT.exists():
        RECEIPT.unlink()
    run(["swift", "test", "-j", "1"])
    iphone, ipad = choose_devices(args.iphone, args.ipad)
    BUILD.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    base = ["xcodebuild", "-project", "Ember.xcodeproj", "-scheme", "Ember", "-derivedDataPath", str(BUILD / "DerivedData"), "CODE_SIGNING_ALLOWED=NO"]
    results = []
    for device, name in [(iphone, "iPhone"), (ipad, "iPad")]:
        result = BUILD / f"{name}-{stamp}.xcresult"
        command = base + ["test", "-destination", f"platform=iOS Simulator,id={device['udid']}", "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result)]
        if name == "iPad":
            command += ["-only-testing:EmberUITests"]
        run(command)
        results.append(str(result.relative_to(ROOT)))
    run(base + ["build", "-configuration", "Release", "-destination", "generic/platform=iOS"])
    RECEIPT.write_text(json.dumps({"validated_at": datetime.now(timezone.utc).isoformat(), "source_sha256": fingerprint(), "xcode": version, "iphone": iphone["name"], "ipad": ipad["name"], "results": results, "signed": False}, indent=2) + "\n")
    print("iPhone and iPad tests and the Release device build passed. Signing and manual device review remain.")


def archive(args):
    require_macos()
    settings_file = RELEASE / "release-config.json"
    if not settings_file.exists():
        raise SystemExit("Run configure with your real publisher, team, bundle ID, and support/privacy details first.")
    settings = json.loads(settings_file.read_text())
    if not RECEIPT.exists():
        raise SystemExit("Run validate on this Mac before archiving.")
    receipt = json.loads(RECEIPT.read_text())
    if receipt.get("source_sha256") != fingerprint():
        raise SystemExit("Source or configuration changed since validation. Run validate again.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    archive_path = BUILD / f"Ember-{stamp}.xcarchive"
    provision = ["-allowProvisioningUpdates"] if args.allow_provisioning_updates else []
    run(["xcodebuild", "-project", "Ember.xcodeproj", "-scheme", "Ember", "-configuration", "Release", "-destination", "generic/platform=iOS", "-archivePath", archive_path, "archive"] + provision)
    export_options = BUILD / "ExportOptions.plist"
    export_options.write_bytes(plistlib.dumps({"method": "app-store-connect", "destination": "export", "teamID": settings["team"], "signingStyle": "automatic", "uploadSymbols": True, "manageAppVersionAndBuildNumber": False}))
    run(["xcodebuild", "-exportArchive", "-archivePath", archive_path, "-exportPath", BUILD / f"Export-{stamp}", "-exportOptionsPlist", export_options] + provision)
    print("Archive and IPA exported locally. Nothing has been uploaded or published.")


def screenshots(args):
    require_macos()
    result = Path(args.result).expanduser().resolve()
    destination = RELEASE / "screenshots"
    destination.mkdir(exist_ok=True)
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", destination])
    print("Simulator test attachments exported. Review and select full-resolution captures for App Store Connect.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    config = sub.add_parser("configure")
    for flag in ["bundle-id", "team", "support-url", "privacy-url", "support-email", "publisher"]:
        config.add_argument("--" + flag, required=True)
    validation = sub.add_parser("validate")
    validation.add_argument("--core-only", action="store_true")
    validation.add_argument("--iphone")
    validation.add_argument("--ipad")
    archive_parser = sub.add_parser("archive")
    archive_parser.add_argument("--allow-provisioning-updates", action="store_true")
    captures = sub.add_parser("screenshots")
    captures.add_argument("--result", required=True)
    args = parser.parse_args()
    {"configure": configure, "validate": validate, "archive": archive, "screenshots": screenshots}[args.command](args)


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, AssertionError, OSError, ValueError) as error:
        raise SystemExit(f"Stopped: {error}")
