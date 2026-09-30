#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent

def run(args):
    subprocess.run([str(x) for x in args], cwd=ROOT, check=True)

if sys.platform != "darwin":
    raise SystemExit("Native validation requires a Mac with Xcode.")
run(["swift", "test", "-j", "2"])
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devices = [(runtime, item) for runtime, items in data["devices"].items() if "iOS" in runtime for item in items if item.get("isAvailable")]
build = ROOT / "build"; build.mkdir(exist_ok=True)
for kind in ["iPhone", "iPad"]:
    matches = [item for _, item in devices if kind in item["name"]]
    if not matches: raise SystemExit(f"Missing {kind} simulator")
    device = matches[0]
    result = build / f"{kind}.xcresult"
    try:
        run(["xcodebuild", "test", "-project", "Vloh.xcodeproj", "-scheme", "Vloh", "-destination", "platform=iOS Simulator,id=" + device["udid"], "-parallel-testing-enabled", "NO", "-resultBundlePath", result, "CODE_SIGNING_ALLOWED=NO"])
    finally:
        run(["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", build / f"screenshots-{kind}"])
run(["xcodebuild", "build", "-project", "Vloh.xcodeproj", "-scheme", "Vloh", "-configuration", "Release", "-destination", "generic/platform=iOS", "CODE_SIGNING_ALLOWED=NO"])
(build / "validation.json").write_text(json.dumps({"native_tests": "passed", "device_release_build": "passed", "signed": False}))

