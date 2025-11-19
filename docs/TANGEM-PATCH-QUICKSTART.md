# Tangem SDK Patch - Quick Start Guide

## Current Status

✅ **Signature generation & verification**: WORKING  
✅ **Single NFC session**: WORKING  
⚠️ **Multiple scans/15s delays**: STILL OCCURRING due to firmware check

## The Issue

Your Tangem card (firmware 6.33r) supports linked terminals, but the iOS SDK blocks this feature for HD wallets. This causes:
- **3+ NFC scans** per signature
- **15-second delay** each scan
- **45+ seconds** total per signature

## The Solution

Patch the SDK binary to remove the firmware version check, enabling:
- **1-2 NFC scans** per signature
- **15 seconds first time** (terminal linking)
- **<3 seconds after** (terminal recognized)

---

## Quick Start: 3-Step Process

### Step 1: Analyze the Binary (You need Hopper)

**Download Hopper Disassembler:**
- Free trial: https://www.hopperapp.com/download.html
- Or use Ghidra (free): https://ghidra-sre.org/

**In Hopper:**

1. **File** → **Read Executable to Disassemble**
2. Navigate to:
   ```
   /Users/manuelrm/Documents/GitHub/safe-ios/Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk
   ```
3. Click **OK** and wait for analysis (~2-3 minutes)

4. **Search for the target string:**
   - Press `Shift+Cmd+F` (or **Navigate** → **Search for Strings**)
   - Type: `Linked terminal feature disabled`
   - Press Enter

5. **Find the code:**
   - Double-click the search result
   - You'll see the string in the data section
   - Right-click on the string → **References to "Linked terminal..."**
   - Click on the code reference (should be 1-2 results)

6. **Locate the firmware check:**
   - You'll see assembly code like:
     ```assembly
     ; ... some code ...
     ldr     w8, [x19, #0x30]      ; Load firmware version
     mov     w9, #0x4              ; Major = 4
     movk    w9, #0x34, lsl #8     ; Minor = 52 (0x34 << 8)
     cmp     w8, w9                ; Compare versions
     b.lt    loc_send_terminal     ; If < 4.52, send terminal keys
     ; Otherwise, skip terminal (THIS IS THE PATH WE'RE ON NOW)
     adr     x0, aLINKED_TERMINAL  ; "Linked terminal feature disabled..."
     bl      log_message
     ```

7. **Find the branch to patch:**
   - Look for `b.lt` or `b.ge` instruction after the `cmp`
   - Click on that instruction
   - In the bottom panel, note:
     - **File Offset**: e.g., `0x1a2b3c`
     - **Bytes**: e.g., `E8 03 00 54` (this is the instruction in hex)

8. **Record the values:**
   ```
   PATCH_OFFSET=0x1a2b3c       # The file offset
   ORIGINAL_BYTES="E8 03 00 54" # The current instruction bytes
   ```

### Step 2: Apply the Patch

1. **Edit** `scripts/patch-tangem-sdk.sh`:
   - Find lines with `PATCH_OFFSET=0x000000`
   - Replace `0x000000` with your offset (e.g., `0x1a2b3c`)
   - Find `ORIGINAL_BYTES="00 00 00 00"`
   - Replace with your bytes (e.g., `"E8 03 00 54"`)

2. **Run the patch script:**
   ```bash
   cd /Users/manuelrm/Documents/GitHub/safe-ios
   ./scripts/patch-tangem-sdk.sh
   ```

3. **Follow the prompts** - it will:
   - Backup the original framework
   - Verify the patch location
   - Apply NOP instructions
   - Re-sign the binary

### Step 3: Build & Test

1. **Clean Xcode derived data:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*
   ```

2. **In Xcode:**
   - Product → Clean Build Folder (`Cmd+Shift+K`)
   - Product → Build (`Cmd+B`)
   - Run on device

3. **Test signing:**
   - **First signature**: Will still have 15s delay (card learns terminal key)
     - Look for in logs: `TAG_IsLinked = 00` → `01` at end
   - **Second signature**: Should be FAST (<3s), no delay!
     - Look for in logs: `TAG_IsLinked = 01` immediately
     - Look for: `TAG_PauseBeforePin2 = 0000` (no pause!)

---

## Troubleshooting

### Problem: "Bytes don't match"
**Cause**: Wrong offset or SDK version changed  
**Fix**: Re-analyze binary with Hopper, find correct offset

### Problem: App crashes after patch
**Cause**: Patched wrong location or corrupted binary  
**Fix**: 
```bash
./scripts/restore-tangem-sdk.sh
```

### Problem: Still seeing multiple scans
**Cause**: Patch didn't work or card not linking  
**Check**:
1. Verify patch: `./scripts/verify-tangem-patch.sh`
2. Check logs for `TAG_IsLinked` value
3. Ensure `config.linkedTerminal = true` in `TangemService.swift`

### Problem: Need original SDK back
```bash
./scripts/restore-tangem-sdk.sh
```

---

## Alternative: Source-Based Rebuild (If Binary Patching Fails)

If binary patching proves too difficult, we can try rebuilding from source again:

```bash
# Clone Tangem SDK
git clone https://github.com/tangem/tangem-sdk-ios.git
cd tangem-sdk-ios
git checkout 3.24.1  # Or your version

# Apply the source patch
# Edit: TangemSdk/TangemSdk/Operations/Sign/SignCommand.swift
# Remove: card.firmwareVersion < .hdWalletAvailable

# Build for device
xcodebuild archive \
  -project TangemSdk/TangemSdk.xcodeproj \
  -scheme TangemSdk \
  -configuration Release \
  -sdk iphoneos \
  -archivePath build/iOS.xcarchive \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ONLY_ACTIVE_ARCH=NO

# Build for simulator  
xcodebuild archive \
  -project TangemSdk/TangemSdk.xcodeproj \
  -scheme TangemSdk \
  -configuration Release \
  -sdk iphonesimulator \
  -archivePath build/Sim.xcarchive \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ONLY_ACTIVE_ARCH=NO

# Create XCFramework
xcodebuild -create-xcframework \
  -framework build/iOS.xcarchive/Products/Library/Frameworks/TangemSdk.framework \
  -framework build/Sim.xcarchive/Products/Library/Frameworks/TangemSdk.framework \
  -output TangemSdk.xcframework

# Replace in project
rm -rf /path/to/safe-ios/Multisig/Logic/Tangem/TangemSdk.xcframework
cp -R TangemSdk.xcframework /path/to/safe-ios/Multisig/Logic/Tangem/
```

---

## Expected Results After Patch

### Before Patch (Current)
```
Scan 1: Read card → Sign (15s delay) → TAG_IsLinked=00
Scan 2: Reconnect → Resume (15s delay) → TAG_IsLinked=00
Scan 3: Reconnect → Complete (15s delay) → Done
Total: 45+ seconds, 3+ scans
```

### After Patch
```
Scan 1: Read card → Sign (15s delay) → TAG_IsLinked=01 ✨
Scan 2: Sign immediately (<1s) → Done 🚀
Total: ~17 seconds first time, <3 seconds after
```

---

## Files Created

- 📖 `docs/tangem-sdk-binary-patch-plan.md` - Full technical plan
- 📖 `docs/TANGEM-PATCH-QUICKSTART.md` - This file
- 🔧 `scripts/patch-tangem-sdk.sh` - Apply patch
- 🔄 `scripts/restore-tangem-sdk.sh` - Rollback patch
- 🔬 `scripts/analyze-tangem-binary.sh` - Analysis helper
- ✅ `scripts/verify-tangem-patch.sh` - Verify patch applied

## Next Action

**Download Hopper and analyze the binary** following Step 1 above, then proceed to Step 2.

Good luck! 🍀

