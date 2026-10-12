#!/usr/bin/env python3
import json
import os
import subprocess
from PIL import Image

def generate_icons():
    source_path = "assets/icons/app_icon.png"
    if not os.path.exists(source_path):
        print(f"Error: {source_path} does not exist.")
        return

    base_img = Image.open(source_path).convert("RGBA")
    print(f"Loaded master icon: {source_path} ({base_img.size})")

    # 1. macOS 图标集
    macos_dir = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    macos_contents_file = os.path.join(macos_dir, "Contents.json")
    if os.path.exists(macos_contents_file):
        with open(macos_contents_file, "r") as f:
            data = json.load(f)
        for img_info in data.get("images", []):
            filename = img_info.get("filename")
            size_str = img_info.get("size", "0x0")
            scale_str = img_info.get("scale", "1x")
            
            base_size = float(size_str.split("x")[0])
            scale = float(scale_str.replace("x", ""))
            target_px = int(round(base_size * scale))
            
            target_path = os.path.join(macos_dir, filename)
            resized = base_img.resize((target_px, target_px), Image.Resampling.LANCZOS)
            resized.save(target_path, "PNG")
            print(f"  [macOS] Generated {filename} ({target_px}x{target_px})")

        # 使用 iconutil 将其编译为 AppIcon.icns
        try:
            icns_target = "macos/Runner/AppIcon.icns"
            subprocess.run(["iconutil", "-c", "icns", macos_dir, "-o", icns_target], check=True)
            print(f"  [macOS] Successfully generated native {icns_target}")
        except Exception as e:
            print("  [macOS] iconutil warning:", e)

    # 2. iOS 图标集
    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_contents_file = os.path.join(ios_dir, "Contents.json")
    if os.path.exists(ios_contents_file):
        with open(ios_contents_file, "r") as f:
            data = json.load(f)
        for img_info in data.get("images", []):
            filename = img_info.get("filename")
            size_str = img_info.get("size", "0x0")
            scale_str = img_info.get("scale", "1x")
            
            base_size = float(size_str.split("x")[0])
            scale = float(scale_str.replace("x", ""))
            target_px = int(round(base_size * scale))
            
            target_path = os.path.join(ios_dir, filename)
            resized = base_img.resize((target_px, target_px), Image.Resampling.LANCZOS)
            resized.save(target_path, "PNG")
            print(f"  [iOS] Generated {filename} ({target_px}x{target_px})")

    # 3. Android 图标集
    android_res_dir = "android/app/src/main/res"
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in android_sizes.items():
        dest = os.path.join(android_res_dir, folder, "launcher_icon.png")
        if os.path.exists(os.path.dirname(dest)):
            resized = base_img.resize((px, px), Image.Resampling.LANCZOS)
            resized.save(dest, "PNG")
            print(f"  [Android] Generated {dest} ({px}x{px})")

    # 4. Web 图标集
    web_icons = {
        "web/favicon.png": 32,
        "web/icons/Icon-192.png": 192,
        "web/icons/Icon-512.png": 512,
        "web/icons/Icon-maskable-192.png": 192,
        "web/icons/Icon-maskable-512.png": 512,
    }
    for dest, px in web_icons.items():
        if os.path.exists(os.path.dirname(dest)):
            resized = base_img.resize((px, px), Image.Resampling.LANCZOS)
            resized.save(dest, "PNG")
            print(f"  [Web] Generated {dest} ({px}x{px})")

    # 5. Linux 图标
    linux_icon = "linux/flutter/assets/icon.png"
    if os.path.exists(os.path.dirname(linux_icon)):
        resized = base_img.resize((256, 256), Image.Resampling.LANCZOS)
        resized.save(linux_icon, "PNG")
        print(f"  [Linux] Generated {linux_icon} (256x256)")

    print("All icons synchronized successfully!")

if __name__ == "__main__":
    generate_icons()
