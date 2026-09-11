#!/usr/bin/env python3
"""Recreate Ember's original geometric icon. Requires Pillow only when regenerating."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
assets = ROOT / "Ember/Resources/Assets.xcassets"
assets.mkdir(parents=True, exist_ok=True)
info = {"author": "xcode", "version": 1}
(assets / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")

for name, light, dark in [
    ("AccentColor", (0.729, 0.239, 0.086), (1.0, 0.541, 0.322)),
    ("LaunchBackground", (1.0, 1.0, 1.0), (0.0, 0.0, 0.0)),
]:
    folder = assets / (name + ".colorset")
    folder.mkdir(exist_ok=True)
    def entry(rgb, dark=False):
        value = {"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": str(rgb[0]), "green": str(rgb[1]), "blue": str(rgb[2]), "alpha": "1.000"}}}
        if dark:
            value["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        return value
    (folder / "Contents.json").write_text(json.dumps({"colors": [entry(light), entry(dark, True)], "info": info}, indent=2) + "\n")

folder = assets / "AppIcon.appiconset"
folder.mkdir(exist_ok=True)
for name, background, foreground in [
    ("AppIcon", "#E65B2C", "#FFF9F1"),
    ("AppIcon-Dark", "#1C1917", "#FF925E"),
    ("AppIcon-Tinted", "#202020", "#FFFFFF"),
]:
    scale = 4
    canvas = Image.new("RGB", (1024 * scale, 1024 * scale), background)
    draw = ImageDraw.Draw(canvas)
    # An E built from the same three lines as the native Stories tab.
    for x1, y1, x2, y2 in [(270, 275, 754, 385), (270, 457, 646, 567), (270, 639, 754, 749)]:
        draw.rounded_rectangle((x1 * scale, y1 * scale, x2 * scale, y2 * scale), radius=22 * scale, fill=foreground)
    canvas.resize((1024, 1024), Image.Resampling.LANCZOS).save(folder / (name + ".png"))

images = [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
for appearance, name in [("dark", "AppIcon-Dark"), ("tinted", "AppIcon-Tinted")]:
    images.append({"filename": name + ".png", "idiom": "universal", "platform": "ios", "size": "1024x1024", "appearances": [{"appearance": "luminosity", "value": appearance}]})
(folder / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
print("Created light, dark, and tinted 1024px opaque app icons and adaptive colors.")
