#!/usr/bin/python3
"""
Generate DMG installer background image with vertical layout.
App at top, downward arrow, Applications folder at bottom.
DARK background with arrow and subtle text label.
"""

import sys
import os


def generate_background(output_path, width, height, app_x, app_y, apps_x, apps_y, win_width, win_height):
    """Generate the installer background image with vertical layout."""

    try:
        from PIL import Image, ImageDraw, ImageFont
        generate_with_pil(output_path, width, height, app_x, app_y, apps_x, apps_y, win_width, win_height)
    except ImportError:
        generate_background_native(output_path, width, height, app_x, app_y, apps_x, apps_y, win_width, win_height)


def generate_with_pil(output_path, width, height, app_x, app_y, apps_x, apps_y, win_width, win_height):
    """Generate background using PIL - dark background with smooth arrow and text."""
    from PIL import Image, ImageDraw, ImageFont

    # Pure black background
    bg_color = (0, 0, 0)

    # Create at 3x resolution for anti-aliasing, then scale down
    scale = 3
    img = Image.new('RGB', (width * scale, height * scale), bg_color)
    draw = ImageDraw.Draw(img)

    # Arrow parameters - pointing DOWN, short arrow between icons
    arrow_color = (140, 145, 155)  # Slightly brighter gray for visibility
    arrow_x = (win_width // 2) * scale  # Centered
    arrow_start_y = (app_y + 80) * scale  # Below app icon
    arrow_end_y = (apps_y - 70) * scale  # Well above Applications icon

    # Draw arrow shaft (thicker for smoothness)
    shaft_width = 6 * scale
    shaft_end_y = arrow_end_y - (4 * scale)  # Leave room for arrow head
    draw.rectangle([arrow_x - shaft_width//2, arrow_start_y,
                    arrow_x + shaft_width//2, shaft_end_y],
                   fill=arrow_color)

    # Draw arrow head (pointing down) - larger and smoother
    head_width = 30 * scale
    head_height = 20 * scale
    arrow_head = [
        (arrow_x, shaft_end_y + head_height),  # Bottom point
        (arrow_x - head_width//2, shaft_end_y),  # Top left
        (arrow_x + head_width//2, shaft_end_y),  # Top right
    ]
    draw.polygon(arrow_head, fill=arrow_color)

    # Draw "Drag to Applications" text below the Applications icon area
    text_color = (100, 105, 115)
    text_y = (apps_y + 75) * scale
    text_x = (win_width // 2) * scale

    # Try to use a system font, fall back to default
    font = None
    font_size = 13 * scale
    for font_path in [
        "/System/Library/Fonts/SFNSText.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Library/Fonts/Arial.ttf",
    ]:
        if os.path.exists(font_path):
            try:
                font = ImageFont.truetype(font_path, font_size)
                break
            except (IOError, OSError):
                continue

    label = "Drag to Applications"
    if font:
        bbox = draw.textbbox((0, 0), label, font=font)
        tw = bbox[2] - bbox[0]
        draw.text((text_x - tw // 2, text_y), label, fill=text_color, font=font)
    else:
        # Default font - approximate centering
        draw.text((text_x - 80 * scale, text_y), label, fill=text_color)

    # Scale down with high-quality resampling for smooth edges
    img = img.resize((width, height), Image.LANCZOS)

    # Save
    img.save(output_path, 'PNG')
    print(f"Generated background with PIL: {output_path}")


def generate_background_native(output_path, width, height, app_x, app_y, apps_x, apps_y, win_width, win_height):
    """Generate background using native macOS tools (no PIL required)."""
    import subprocess

    arrow_x = win_width // 2
    arrow_start_y = app_y + 95
    arrow_end_y = apps_y - 55
    shaft_end_y = arrow_end_y - 2
    text_y = apps_y + 80

    # Create SVG with pure black background
    svg_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">
  <!-- Pure black background -->
  <rect width="100%" height="100%" fill="#000000"/>

  <!-- Arrow shaft -->
  <rect x="{arrow_x - 2}" y="{arrow_start_y}" width="4" height="{max(0, shaft_end_y - arrow_start_y)}"
        fill="#8c919b"/>

  <!-- Arrow head (pointing down) -->
  <polygon points="{arrow_x},{shaft_end_y + 16} {arrow_x - 11},{shaft_end_y} {arrow_x + 11},{shaft_end_y}"
           fill="#8c919b"/>

  <!-- Label text -->
  <text x="{arrow_x}" y="{text_y}" fill="#646973" font-family="Helvetica, Arial, sans-serif"
        font-size="13" text-anchor="middle">Drag to Applications</text>
</svg>'''

    # Write SVG
    svg_path = output_path.replace('.png', '.svg')
    with open(svg_path, 'w') as f:
        f.write(svg_content)

    # Convert SVG to PNG
    converted = False

    try:
        subprocess.run(['rsvg-convert', '-w', str(width), '-h', str(height),
                       '-o', output_path, svg_path], check=True, capture_output=True)
        converted = True
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    if not converted:
        try:
            tmp_dir = os.path.dirname(output_path)
            subprocess.run(['qlmanage', '-t', '-s', str(max(width, height)),
                           '-o', tmp_dir, svg_path],
                          check=True, capture_output=True, timeout=10)
            ql_output = svg_path + '.png'
            if os.path.exists(ql_output):
                os.rename(ql_output, output_path)
                converted = True
        except:
            pass

    if not converted:
        create_png_native(output_path, width, height)

    if os.path.exists(svg_path):
        os.remove(svg_path)

    print(f"Generated background: {output_path}")


def create_png_native(output_path, width, height):
    """Create solid black PNG using only standard library."""
    import struct
    import zlib

    # Pure black background
    bg_r, bg_g, bg_b = 0, 0, 0

    def create_png(w, h, r, g, b):
        def png_chunk(chunk_type, data):
            chunk_len = struct.pack('>I', len(data))
            chunk_crc = struct.pack('>I', zlib.crc32(chunk_type + data) & 0xffffffff)
            return chunk_len + chunk_type + data + chunk_crc

        signature = b'\x89PNG\r\n\x1a\n'
        ihdr_data = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
        ihdr = png_chunk(b'IHDR', ihdr_data)

        raw_data = b''
        row = bytes([r, g, b]) * w
        for y in range(h):
            raw_data += b'\x00' + row

        compressed = zlib.compress(raw_data, 9)
        idat = png_chunk(b'IDAT', compressed)
        iend = png_chunk(b'IEND', b'')

        return signature + ihdr + idat + iend

    png_data = create_png(width, height, bg_r, bg_g, bg_b)

    with open(output_path, 'wb') as f:
        f.write(png_data)

    print(f"Generated solid background: {output_path}")


if __name__ == '__main__':
    if len(sys.argv) < 10:
        print("Usage: generate_background.py <output.png> <width> <height> <app_x> <app_y> <apps_x> <apps_y> <win_width> <win_height>")
        sys.exit(1)

    output_path = sys.argv[1]
    width = int(sys.argv[2])
    height = int(sys.argv[3])
    app_x = int(sys.argv[4])
    app_y = int(sys.argv[5])
    apps_x = int(sys.argv[6])
    apps_y = int(sys.argv[7])
    win_width = int(sys.argv[8])
    win_height = int(sys.argv[9])

    generate_background(output_path, width, height, app_x, app_y, apps_x, apps_y, win_width, win_height)
