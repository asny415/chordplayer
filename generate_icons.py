#!/usr/bin/env python3
"""
生成macOS应用图标的不同尺寸版本
"""

import os
from PIL import Image, ImageDraw
import cairosvg
import io

def create_guitar_icon(size):
    """创建一个指定尺寸的吉他图标"""
    # 创建画布
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # 计算比例
    scale = size / 512
    
    # 背景圆形
    margin = int(20 * scale)
    bg_size = size - 2 * margin
    draw.ellipse([margin, margin, margin + bg_size, margin + bg_size], 
                fill=(102, 126, 234, 255))  # 渐变背景的中间色
    
    # 吉他主体
    center_x, center_y = size // 2, size // 2
    guitar_width = int(200 * scale)
    guitar_height = int(120 * scale)
    
    # 吉他身体
    body_rect = [center_x - guitar_width//2, center_y - guitar_height//2 + int(40*scale),
                 center_x + guitar_width//2, center_y + guitar_height//2 + int(40*scale)]
    draw.ellipse(body_rect, fill=(255, 255, 255, 240))
    
    # 吉他琴颈
    neck_width = int(200 * scale)
    neck_height = int(30 * scale)
    neck_rect = [center_x - neck_width//2, center_y - int(160*scale),
                 center_x + neck_width//2, center_y - int(160*scale) + neck_height]
    draw.rounded_rectangle(neck_rect, radius=int(14*scale), fill=(255, 255, 255, 240))
    
    # 琴头
    head_width = int(280 * scale)
    head_height = int(60 * scale)
    head_rect = [center_x - head_width//2, center_y - int(200*scale),
                 center_x + head_width//2, center_y - int(200*scale) + head_height]
    draw.rounded_rectangle(head_rect, radius=int(30*scale), fill=(255, 255, 255, 240))
    
    # 调音钮
    tuner_size = int(12 * scale)
    tuner_positions = [(-100, -170), (-50, -170), (50, -170), (100, -170)]
    for x, y in tuner_positions:
        tuner_x = center_x + int(x * scale)
        tuner_y = center_y + int(y * scale)
        draw.ellipse([tuner_x - tuner_size//2, tuner_y - tuner_size//2,
                     tuner_x + tuner_size//2, tuner_y + tuner_size//2],
                    fill=(102, 126, 234, 255))
    
    # 琴弦
    string_width = int(4 * scale)
    string_positions = [-100, -50, 50, 100]
    for x in string_positions:
        string_x = center_x + int(x * scale)
        start_y = center_y - int(140 * scale)
        end_y = center_y + int(40 * scale)
        draw.rectangle([string_x - string_width//2, start_y,
                       string_x + string_width//2, end_y],
                      fill=(102, 126, 234, 200))
    
    # 音孔
    sound_hole_radius = int(40 * scale)
    draw.ellipse([center_x - sound_hole_radius, center_y - sound_hole_radius + int(40*scale),
                 center_x + sound_hole_radius, center_y + sound_hole_radius + int(40*scale)],
                fill=(255, 107, 107, 255))
    
    # 音孔内圈
    inner_radius = int(30 * scale)
    draw.ellipse([center_x - inner_radius, center_y - inner_radius + int(40*scale),
                 center_x + inner_radius, center_y + inner_radius + int(40*scale)],
                fill=(255, 255, 255, 255))
    
    # 装饰音符
    note_size = int(16 * scale)
    note_positions = [(-60, -80), (60, -80)]
    for x, y in note_positions:
        note_x = center_x + int(x * scale)
        note_y = center_y + int(y * scale)
        # 音符主体
        draw.ellipse([note_x - note_size//2, note_y - note_size//2,
                     note_x + note_size//2, note_y + note_size//2],
                    fill=(255, 107, 107, 255))
        # 音符杆
        draw.rectangle([note_x + note_size//2 - 2, note_y - note_size,
                       note_x + note_size//2 + 2, note_y + note_size//2],
                      fill=(255, 107, 107, 255))
    
    return img

def generate_icons():
    """生成所有需要的图标尺寸"""
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]
    
    # 创建输出目录
    output_dir = "guitarPlayer/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(output_dir, exist_ok=True)
    
    for size, filename in sizes:
        print(f"生成 {filename} ({size}x{size})")
        icon = create_guitar_icon(size)
        icon.save(os.path.join(output_dir, filename), "PNG")
    
    print("所有图标已生成完成！")

if __name__ == "__main__":
    generate_icons()
