import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

def get_chinese_font(size):
    # 优先使用 macOS 内置的冬青黑体 / 华文黑体，100% 包含完整中文 CJK 字形
    candidate_fonts = [
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for font_path in candidate_fonts:
        if os.path.exists(font_path):
            try:
                return ImageFont.truetype(font_path, size)
            except Exception:
                continue
    return None

def get_english_font(size):
    candidate_fonts = [
        "/System/Library/Fonts/SFProText-Regular.otf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for font_path in candidate_fonts:
        if os.path.exists(font_path):
            try:
                return ImageFont.truetype(font_path, size)
            except Exception:
                continue
    return None

def draw_background(width, height, scale=1):
    img = Image.new('RGBA', (width, height), (248, 249, 252, 255))
    draw = ImageDraw.Draw(img)

    # 1. 柔和的现代 macOS 微渐变背景底色
    for y in range(height):
        ratio = y / height
        r = int(249 - ratio * 8)
        g = int(250 - ratio * 7)
        b = int(253 - ratio * 5)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

    # 2. 绘制中间指示箭头 (位于左图标 x=175 与右图标 x=485 正中间，中心 x=330, y=175)
    center_x = int(330 * scale)
    center_y = int(175 * scale)

    capsule_w = int(90 * scale)
    capsule_h = int(34 * scale)
    capsule_r = int(17 * scale)
    
    capsule_box = [
        center_x - capsule_w // 2,
        center_y - capsule_h // 2,
        center_x + capsule_w // 2,
        center_y + capsule_h // 2
    ]
    # 胶囊背景
    draw.rounded_rectangle(capsule_box, radius=capsule_r, fill=(228, 233, 242, 220), outline=(210, 216, 228, 255), width=int(1 * scale))

    # 箭头本体
    arrow_color = (120, 130, 150, 240)
    shaft_len = int(36 * scale)
    shaft_x1 = center_x - shaft_len // 2
    shaft_x2 = center_x + shaft_len // 2
    draw.line([(shaft_x1, center_y), (shaft_x2, center_y)], fill=arrow_color, width=int(4 * scale))

    head_len = int(10 * scale)
    draw.polygon([
        (shaft_x2, center_y - head_len),
        (shaft_x2 + int(12 * scale), center_y),
        (shaft_x2, center_y + head_len)
    ], fill=arrow_color)

    # 3. 字体加载：确保中文使用 Hiragino Sans GB (冬青黑体)
    font_cn = get_chinese_font(int(14 * scale))
    font_en = get_english_font(int(11 * scale)) or font_cn

    title_text = "拖拽 Authix 到 Applications 文件夹以完成安装"
    subtitle_text = "Drag Authix to Applications folder to install"

    if font_cn is not None:
        try:
            bbox1 = draw.textbbox((0, 0), title_text, font=font_cn)
            w1 = bbox1[2] - bbox1[0]
            draw.text(((width - w1) // 2, int(295 * scale)), title_text, fill=(80, 90, 110, 240), font=font_cn)
        except Exception as e:
            print("Error rendering Chinese text:", e)
    
    if font_en is not None:
        try:
            bbox2 = draw.textbbox((0, 0), subtitle_text, font=font_en)
            w2 = bbox2[2] - bbox2[0]
            draw.text(((width - w2) // 2, int(320 * scale)), subtitle_text, fill=(130, 140, 160, 200), font=font_en)
        except Exception as e:
            print("Error rendering English text:", e)

    return img

def main():
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'dmg')
    os.makedirs(output_dir, exist_ok=True)

    img_1x_path = os.path.join(output_dir, 'background.png')
    img_2x_path = os.path.join(output_dir, 'background@2x.png')
    tiff_path = os.path.join(output_dir, 'background.tiff')

    # 生成 1x (660 x 450)
    img_1x = draw_background(660, 450, scale=1)
    img_1x.save(img_1x_path, 'PNG')

    # 生成 2x (1320 x 900)
    img_2x = draw_background(1320, 900, scale=2)
    img_2x.save(img_2x_path, 'PNG')

    # 使用 macOS 系统自带 tiffutil 合成标准多分辨率 HiDPI TIFF
    try:
        subprocess.run(['tiffutil', '-cathidpicheck', img_1x_path, img_2x_path, '-out', tiff_path], check=True)
        print(f"HiDPI TIFF successfully created: {tiff_path}")
    except Exception as e:
        print(f"tiffutil fallback: {e}")

    print("DMG backgrounds with proper Chinese fonts generated.")

if __name__ == '__main__':
    main()
