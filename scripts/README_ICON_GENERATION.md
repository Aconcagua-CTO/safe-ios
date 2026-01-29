# App Icon Generation for Build Environments

## Overview

This project uses environment-specific app icons to visually distinguish between different build configurations:

- **Production**: Original icon (no colored line)
- **Staging**: Icon with thin yellow line at the bottom
- **Development**: Icon with thin green line at the bottom

## Icon Locations

All icons are stored in `Multisig/Assets.xcassets/`:

- `AppIcon_PROD.appiconset/` - Production icons (source/original)
- `AppIcon_STAGING.appiconset/` - Staging icons (yellow line)
- `AppIcon_DEV.appiconset/` - Development icons (green line)

## Automatic Icon Selection

The build system automatically selects the correct icon set based on the build configuration:

```xcconfig
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon_$(SERVICE_ENV)
```

Where `SERVICE_ENV` is set in each configuration file:
- `Development.xcconfig`: `SERVICE_ENV = DEV`
- `Staging.xcconfig`: `SERVICE_ENV = STAGING`
- `Production.xcconfig`: `SERVICE_ENV = PROD`

## Regenerating Icons

To regenerate the staging and development icons from the production icons:

```bash
# Generate staging icons (yellow line)
python3 scripts/generate_env_icons.py --env staging

# Generate development icons (green line)
python3 scripts/generate_env_icons.py --env dev
```

### Requirements

- Python 3.x
- Pillow (PIL): `pip install Pillow`

### Script Details

The `generate_env_icons.py` script:
- Reads all PNG files from `AppIcon_PROD.appiconset/`
- Adds a colored line at the bottom (6% of image height)
- Outputs to the corresponding environment iconset folder
- Preserves image quality and alpha channel

**Colors:**
- Staging: RGB(255, 215, 0) - Yellow (#FFD700)
- Development: RGB(0, 255, 0) - Green (#00FF00)

**Line thickness:** 6% of icon height (thin, subtle indicator)

## Icon Sizes

Each iconset contains 18 PNG files covering all iOS app icon sizes:

### iPhone
- 20x20pt (@2x, @3x)
- 29x29pt (@2x, @3x)
- 40x40pt (@2x, @3x)
- 60x60pt (@2x, @3x)

### iPad
- 20x20pt (@1x, @2x)
- 29x29pt (@1x, @2x)
- 40x40pt (@1x, @2x)
- 76x76pt (@1x, @2x)
- 83.5x83.5pt (@2x)

### App Store
- 1024x1024pt (@1x)

## Updating Production Icons

To update the production icons:

1. Replace the PNG files in `AppIcon_PROD.appiconset/`
2. Run the generation script for both environments:
   ```bash
   python3 scripts/generate_env_icons.py --env staging
   python3 scripts/generate_env_icons.py --env dev
   ```

This ensures all three iconsets remain consistent with only the colored line differentiating them.

## Build Configuration

No code or configuration changes are needed. The project already has:
- ✅ Separate iconset folders for each environment
- ✅ Build configurations (Debug/Release × Dev/Staging/Production)
- ✅ Xcode schemes for each environment
- ✅ Automatic icon selection via `ASSETCATALOG_COMPILER_APPICON_NAME`

Simply build with the appropriate scheme and the correct icon will be used automatically.
