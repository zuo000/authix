import colorsys
import os
from PIL import Image

def recolor_icon(
    input_path="/tmp/original_icon.png",
    output_path="assets/icons/app_icon.png",
    target_hue=216.0 / 360.0,  # 目标色相：216度 (高端科技蓝 / 蓝宝石色)
):
    """
    保持原图标的完整造型、透明度、明暗光影 100% 不变，
    仅将紫色系像素的色相精确映射为美观大气的科技宝石蓝色调。
    """
    img = Image.open(input_path).convert("RGBA")
    width, height = img.size
    pixels = img.load()

    # 原始紫色色相中心约为 263° (263 / 360 = 0.7305)
    purple_center = 263.0 / 360.0

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue

            # 转换为 HLS 色彩空间
            h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)

            # 判断是否属于紫色区间 (230° ~ 300°)
            h_deg = h * 360.0
            if 225.0 <= h_deg <= 305.0 and s > 0.05:
                # 保留其与中心紫色色相的微小偏离度，平滑映射到 target_hue
                hue_delta = (h - purple_center)
                new_h = (target_hue + hue_delta) % 1.0

                # 略微微调饱和度，使蓝色更加晶莹纯粹、耐看
                new_s = min(1.0, s * 1.05)
                new_l = l

                new_r, new_g, new_b = colorsys.hls_to_rgb(new_h, new_l, new_s)
                pixels[x, y] = (
                    int(round(new_r * 255.0)),
                    int(round(new_g * 255.0)),
                    int(round(new_b * 255.0)),
                    a,
                )

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")
    print(f"Recolored icon successfully saved to {output_path}")

if __name__ == "__main__":
    recolor_icon()
