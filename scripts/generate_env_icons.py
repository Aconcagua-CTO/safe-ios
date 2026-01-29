#!/usr/bin/env python3
"""
Generate environment-specific app icons by adding colored lines to the bottom of production icons.

Usage:
    python generate_env_icons.py --env staging  # Yellow line
    python generate_env_icons.py --env dev      # Green line
"""

import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw

# Color definitions
COLORS = {
    'staging': (255, 215, 0),   # Yellow #FFD700
    'dev': (0, 255, 0),          # Green #00FF00
}

# Environment folder mapping
ENV_FOLDERS = {
    'staging': 'AppIcon_STAGING.appiconset',
    'dev': 'AppIcon_DEV.appiconset',
}

def _parse_points_size(size_str: str) -> tuple[float, float]:
    w_str, h_str = size_str.split("x", 1)
    return float(w_str), float(h_str)

def _parse_scale(scale_str: str) -> int:
    # e.g. "2x" -> 2
    if not scale_str.endswith("x"):
        raise ValueError(f"Unexpected scale format: {scale_str}")
    return int(scale_str[:-1])

def _pixels_from_asset_entry(size_str: str, scale_str: str) -> tuple[int, int]:
    w_pt, h_pt = _parse_points_size(size_str)
    scale = _parse_scale(scale_str)
    # Typical case: 83.5 * 2 = 167
    w_px = int(round(w_pt * scale))
    h_px = int(round(h_pt * scale))
    return w_px, h_px

def add_colored_line(input_path, output_path, color, line_thickness_ratio=0.06):
    """
    Add a colored line at the bottom of an icon image.
    
    Args:
        input_path: Path to the input PNG file
        output_path: Path to save the modified PNG file
        color: RGB tuple (r, g, b)
        line_thickness_ratio: Ratio of line height to image height (default 0.06 = 6%)
    """
    # Open the image
    img = Image.open(input_path)
    
    # Ensure we're working with RGBA mode
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # Calculate line height
    width, height = img.size
    line_height = int(height * line_thickness_ratio)
    
    # Create a drawing context
    draw = ImageDraw.Draw(img)
    
    # Draw the colored line at the bottom
    # Rectangle from bottom to line_height pixels up
    draw.rectangle(
        [(0, height - line_height), (width, height)],
        fill=color + (255,)  # Add alpha channel (fully opaque)
    )
    
    # Save the image
    img.save(output_path, 'PNG', optimize=True)
    print(f"✓ Processed: {output_path.name}")

def process_icons(env):
    """
    Process all icons for a specific environment.
    
    Args:
        env: Environment name ('staging' or 'dev')
    """
    if env not in COLORS:
        raise ValueError(f"Invalid environment: {env}. Must be 'staging' or 'dev'")
    
    color = COLORS[env]
    env_folder = ENV_FOLDERS[env]
    
    # Get the script directory and navigate to the assets folder
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    assets_dir = project_root / 'Multisig' / 'Assets.xcassets'
    
    prod_folder = assets_dir / 'AppIcon_PROD.appiconset'
    target_folder = assets_dir / env_folder
    
    if not prod_folder.exists():
        raise FileNotFoundError(f"Production icon folder not found: {prod_folder}")
    
    if not target_folder.exists():
        raise FileNotFoundError(f"Target icon folder not found: {target_folder}")
    
    print(f"\n{'='*60}")
    print(f"Processing {env.upper()} icons")
    print(f"Color: RGB{color}")
    print(f"Source: {prod_folder}")
    print(f"Target: {target_folder}")
    print(f"{'='*60}\n")
    
    # Build a lookup of production icons by pixel dimensions (w, h)
    prod_pngs = sorted(prod_folder.glob("*.png"))
    if not prod_pngs:
        raise FileNotFoundError(f"No PNG files found in {prod_folder}")

    prod_by_size: dict[tuple[int, int], Path] = {}
    for p in prod_pngs:
        try:
            with Image.open(p) as im:
                prod_by_size[im.size] = p
        except Exception:
            # Ignore unreadable images
            pass

    # Prefer processing the filenames referenced by the target appiconset Contents.json,
    # because different environments use different filenames (e.g. 120px-1.png).
    contents_path = target_folder / "Contents.json"
    if not contents_path.exists():
        raise FileNotFoundError(f"Missing Contents.json in {target_folder}")

    contents = json.loads(contents_path.read_text(encoding="utf-8"))
    images = contents.get("images", [])

    processed_count = 0
    expected_count = 0
    for entry in images:
        filename = entry.get("filename")
        size_str = entry.get("size")
        scale_str = entry.get("scale")
        if not filename or not size_str or not scale_str:
            continue

        expected_count += 1
        output_path = target_folder / filename

        try:
            target_px = _pixels_from_asset_entry(size_str, scale_str)
            input_path = prod_by_size.get(target_px)
            if input_path is None:
                # Fallback: if the file already exists in target, use it as input
                if output_path.exists():
                    input_path = output_path
                else:
                    raise FileNotFoundError(
                        f"No production icon found for {filename} ({target_px[0]}x{target_px[1]})"
                    )

            add_colored_line(input_path, output_path, color)
            processed_count += 1
        except Exception as e:
            print(f"✗ Error processing {filename}: {e}")
    
    print(f"\n{'='*60}")
    print(f"✓ Complete! Processed {processed_count}/{expected_count} icons")
    print(f"{'='*60}\n")

def main():
    parser = argparse.ArgumentParser(
        description='Generate environment-specific app icons with colored lines'
    )
    parser.add_argument(
        '--env',
        choices=['staging', 'dev'],
        required=True,
        help='Environment to generate icons for (staging=yellow, dev=green)'
    )
    
    args = parser.parse_args()
    
    try:
        process_icons(args.env)
    except Exception as e:
        print(f"\n✗ Error: {e}")
        return 1
    
    return 0

if __name__ == '__main__':
    exit(main())
