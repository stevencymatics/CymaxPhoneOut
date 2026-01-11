#!/usr/bin/env python3
"""Generate a cool app icon for Mix Link"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math
import os

def create_icon(size):
    """Create icon at specified size"""
    # Create image with transparency
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Scale factor for drawing
    s = size / 1024.0
    
    # Background color - dark
    bg_color = (18, 18, 20, 255)
    
    # Draw circular background
    margin = int(20 * s)
    draw.ellipse(
        [margin, margin, size - margin, size - margin],
        fill=bg_color
    )
    
    # Create a separate layer for the glow effect
    glow_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    
    # Cyan color
    cyan = (0, 212, 255)
    teal = (0, 255, 200)
    
    # Center of icon
    cx, cy = size // 2, size // 2
    
    # Draw waveform bars with glow - 5 bars with varied heights
    num_bars = 5
    bar_width = int(65 * s)
    bar_spacing = int(110 * s)
    total_width = (num_bars - 1) * bar_spacing + bar_width  # Include bar width in total
    start_x = cx - total_width // 2  # Center properly
    
    # Waveform heights - dramatic variation
    heights = [0.35, 0.75, 1.0, 0.6, 0.25]
    max_height = int(450 * s)
    
    # First pass - draw glow (larger, blurred)
    for i, h in enumerate(heights):
        bar_height = int(max_height * h)
        x = start_x + i * bar_spacing
        y1 = cy - bar_height // 2
        y2 = cy + bar_height // 2
        
        # Glow bar (wider)
        glow_draw.rounded_rectangle(
            [x - int(10*s), y1 - int(10*s), x + bar_width + int(10*s), y2 + int(10*s)],
            radius=int(30 * s),
            fill=(*cyan, 100)
        )
    
    # Blur the glow layer
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=int(30 * s)))
    
    # Composite glow onto main image
    img = Image.alpha_composite(img, glow_layer)
    draw = ImageDraw.Draw(img)
    
    # Second pass - draw actual bars using circles + rectangle (avoids center line artifact)
    for i, h in enumerate(heights):
        bar_height = int(max_height * h)
        x = start_x + i * bar_spacing
        y1 = cy - bar_height // 2
        y2 = cy + bar_height // 2
        
        # Radius for rounded ends
        radius = bar_width // 2
        
        # Draw top circle
        draw.ellipse(
            [x, y1, x + bar_width, y1 + bar_width],
            fill=cyan
        )
        
        # Draw bottom circle
        draw.ellipse(
            [x, y2 - bar_width, x + bar_width, y2],
            fill=cyan
        )
        
        # Draw middle rectangle (overlaps with circles)
        draw.rectangle(
            [x, y1 + radius, x + bar_width, y2 - radius],
            fill=cyan
        )
    
    return img


def main():
    # Output directory
    output_dir = "/Users/stevencymatics/Documents/Phone Audio Project/mac/CymaxPhoneOutMenubar/CymaxPhoneOutMenubar/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(output_dir, exist_ok=True)
    
    # macOS icon sizes needed
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    
    # Generate icons
    for size in sizes:
        print(f"Generating {size}x{size} icon...")
        icon = create_icon(size)
        
        # Save 1x version
        icon.save(os.path.join(output_dir, f"icon_{size}x{size}.png"))
        
        # For retina (2x), generate at double size if not already max
        if size <= 512:
            icon_2x = create_icon(size * 2)
            icon_2x.save(os.path.join(output_dir, f"icon_{size}x{size}@2x.png"))
    
    # Create Contents.json
    contents = {
        "images": [
            {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
            {"filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
            {"filename": "icon_32x32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
            {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
            {"filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
            {"filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"}
        ],
        "info": {"author": "xcode", "version": 1}
    }
    
    import json
    with open(os.path.join(output_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)
    
    # Create Assets.xcassets Contents.json
    assets_dir = os.path.dirname(output_dir)
    with open(os.path.join(assets_dir, "Contents.json"), 'w') as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    
    print(f"\n✅ Icons generated in {output_dir}")
    print("Now update Xcode project to include Assets.xcassets")


if __name__ == "__main__":
    main()

