#!/bin/bash
# Script to validate NFC entitlements in provisioning profiles and signed app

set -e

echo "=== NFC Entitlements Validation Script ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Check provisioning profiles
echo "Step 1: Checking Provisioning Profiles..."
echo "----------------------------------------"

PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
BUNDLE_ID="com.manuelrm.bovedapp.dev.mainnet"

if [ ! -d "$PROFILE_DIR" ]; then
    echo -e "${YELLOW}Warning: Provisioning profiles directory not found${NC}"
    echo "Directory: $PROFILE_DIR"
    echo ""
else
    echo "Searching for profiles matching bundle ID: $BUNDLE_ID"
    echo ""
    
    FOUND_PROFILES=0
    
    for profile in "$PROFILE_DIR"/*.mobileprovision; do
        if [ -f "$profile" ]; then
            # Extract bundle ID from profile
            PROFILE_BUNDLE_ID=$(security cms -D -i "$profile" 2>/dev/null | grep -A 1 "application-identifier" | grep -o 'com\.[^<]*' | head -1)
            
            if [[ "$PROFILE_BUNDLE_ID" == *"$BUNDLE_ID"* ]] || [[ "$PROFILE_BUNDLE_ID" == *"*"* ]]; then
                FOUND_PROFILES=$((FOUND_PROFILES + 1))
                echo -e "${GREEN}Found profile: $(basename "$profile")${NC}"
                echo "Bundle ID: $PROFILE_BUNDLE_ID"
                
                # Extract NFC formats
                echo "NFC Formats in profile:"
                NFC_FORMATS=$(security cms -D -i "$profile" 2>/dev/null | grep -A 10 "nfc.readersession.formats" | grep -o '<string>[^<]*</string>' | sed 's/<string>//g' | sed 's/<\/string>//g' | tr '\n' ' ')
                
                if [ -z "$NFC_FORMATS" ]; then
                    echo -e "${RED}  ❌ No NFC formats found in profile${NC}"
                else
                    echo -e "${GREEN}  ✅ Formats: $NFC_FORMATS${NC}"
                    
                    # Check for specific formats
                    if echo "$NFC_FORMATS" | grep -q "ISO7816"; then
                        echo -e "${GREEN}  ✅ ISO7816 format is present${NC}"
                    else
                        echo -e "${YELLOW}  ⚠️  ISO7816 format is NOT present${NC}"
                    fi
                    
                    if echo "$NFC_FORMATS" | grep -q "TAG"; then
                        echo -e "${GREEN}  ✅ TAG format is present${NC}"
                    else
                        echo -e "${RED}  ❌ TAG format is NOT present${NC}"
                    fi
                fi
                echo ""
            fi
        fi
    done
    
    if [ $FOUND_PROFILES -eq 0 ]; then
        echo -e "${YELLOW}No profiles found matching bundle ID: $BUNDLE_ID${NC}"
        echo "This might mean:"
        echo "  1. Profiles haven't been downloaded yet"
        echo "  2. Xcode uses automatic signing and profiles are managed differently"
        echo "  3. Bundle ID doesn't match"
        echo ""
    fi
fi

# Step 2: Check signed app entitlements (if app is built)
echo "Step 2: Checking Signed App Entitlements"
echo "----------------------------------------"
echo "Note: This requires a built app. Run this after building the app."
echo ""

# Try to find built app
BUILD_DIR="Build"
if [ -d "$BUILD_DIR" ]; then
    echo "Looking for built app in $BUILD_DIR..."
    APP_PATH=$(find "$BUILD_DIR" -name "*.app" -type d | head -1)
    
    if [ -n "$APP_PATH" ]; then
        echo -e "${GREEN}Found app: $APP_PATH${NC}"
        echo ""
        echo "NFC Entitlements in signed app:"
        ENTITLEMENTS=$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -A 10 "nfc.readersession.formats" | grep -o '<string>[^<]*</string>' | sed 's/<string>//g' | sed 's/<\/string>//g' | tr '\n' ' ')
        
        if [ -z "$ENTITLEMENTS" ]; then
            echo -e "${RED}  ❌ No NFC entitlements found in signed app${NC}"
        else
            echo -e "${GREEN}  ✅ Formats: $ENTITLEMENTS${NC}"
            
            if echo "$ENTITLEMENTS" | grep -q "ISO7816"; then
                echo -e "${GREEN}  ✅ ISO7816 format is present${NC}"
            else
                echo -e "${YELLOW}  ⚠️  ISO7816 format is NOT present${NC}"
            fi
            
            if echo "$ENTITLEMENTS" | grep -q "TAG"; then
                echo -e "${GREEN}  ✅ TAG format is present${NC}"
            else
                echo -e "${RED}  ❌ TAG format is NOT present${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}No built app found. Build the app first to check signed entitlements.${NC}"
    fi
else
    echo -e "${YELLOW}Build directory not found. Build the app first to check signed entitlements.${NC}"
fi

echo ""
echo "=== Validation Complete ==="
echo ""
echo "Next Steps:"
echo "1. Check App ID configuration in Apple Developer Portal"
echo "2. Verify NFC formats are enabled in App ID"
echo "3. Regenerate provisioning profiles if needed"
echo "4. Rebuild app and test NFC scanning"

