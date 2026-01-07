# Tangem SDK Binary Patch - Detailed Implementation Plan

## Objective
Remove the firmware version check from Tangem SDK's `SignCommand` to enable linked terminal support for HD wallets (firmware 6.33+), eliminating the 15-second security delay.

## Background

### The Problem
The Tangem SDK contains this check in `SignCommand.swift`:
```swift
guard let card = environment.card,
      card.settings.isLinkedTerminalEnabled,
      card.firmwareVersion < .hdWalletAvailable else {  // ← This check prevents HD wallets
          return nil
      }
```

When `firmwareVersion >= .hdWalletAvailable` (4.52+), the SDK **doesn't send** `TAG_TerminalPublicKey` and `TAG_TerminalTransactionSignature`, preventing the card from recognizing us as a linked terminal.

### Why Binary Patching
- **Cannot rebuild from source**: The `.xcframework` requires Tangem's internal build setup and dependencies
- **Cannot runtime swizzle**: SDK classes/methods are internal, not exposed
- **Binary patching**: Directly modify the compiled ARM64 instructions to skip the check

---

## Technical Analysis

### Target Binary
```
File: Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk
Type: Mach-O 64-bit dynamically linked shared library arm64
Size: 4.8M
```

### Key Strings Found
- Offset `0x3d67a2`: `"Using terminal keys (public key len="`
- Offset `0x3d6712`: `"Linked terminal feature disabled on card firmware "`

The code that logs "Linked terminal feature disabled" is where the firmware check **fails**. We need to find the branch instruction that leads to this path and either:
1. **NOP it out** (make it always pass)
2. **Invert the branch** (reverse the condition)

---

## Patch Strategy: Detailed Steps

### Step 1: Locate the Firmware Comparison

**Method 1: Static Analysis with Hopper/IDA**

If you have Hopper Disassembler or IDA Pro:
1. Open `TangemSdk` binary in Hopper
2. Go to address containing string `0x3d6712`
3. Find cross-references (Xrefs) to this string
4. Navigate to the function that references it
5. Look for comparison like:
   ```assembly
   ldr     w8, [x20, #0x...] ; Load firmware version
   cmp     w8, #0x434        ; Compare with 4.52 (0x0434)
   b.ge    loc_skip_terminal ; Branch if >= (skip terminal keys)
   ```

**Method 2: Runtime Debugging with LLDB**

1. Attach debugger to running app
2. Set symbolic breakpoint on string:
   ```lldb
   br set -n "swift_stringFromUTF8"
   command add
   po $arg1
   c
   end
   ```
3. When "Linked terminal feature disabled" appears, examine backtrace
4. Disassemble the calling function to find the branch

**Method 3: Pattern Matching (Fastest for our case)**

Since we know the logic, we can search for a common ARM64 pattern:
```assembly
; Typical pattern for: if (firmwareVersion < 4.52)
mov     w8, #0x4          ; Major version 4
movk    w8, #0x34, lsl #8 ; Minor version 52 (0x34)
cmp     w9, w8            ; Compare current firmware
b.lt    send_terminal     ; Branch if less than (OLD: send keys)
; (skip terminal - NEW CODE PATH WE WANT)
```

### Step 2: Identify the Exact Patch

Once we find the branch, we have these options:

**Option A: NOP the Branch (Safest)**
```assembly
Before: b.ge  0x12345  ; Skip if firmware >= 4.52
After:  nop             ; Always continue (send terminal keys)
        nop
```
ARM64 NOP: `0x1F2003D5`

**Option B: Invert Branch Condition**
```assembly
Before: b.ge  0x12345  ; Branch if >= 4.52
After:  b.lt  0x12345  ; Branch if < 4.52 (inverted)
```
Just change the condition code byte (1 byte change)

**Option C: Force Comparison Result**
```assembly
Before: cmp  w9, w8     ; Compare versions
After:  cmp  w9, #0xFF  ; Always less than
```

### Step 3: Create Backup & Apply Patch

**Script: `scripts/patch-tangem-sdk.sh`**

```bash
#!/bin/bash
set -e

FRAMEWORK_DIR="Multisig/Logic/Tangem/TangemSdk.xcframework"
BINARY_PATH="$FRAMEWORK_DIR/ios-arm64/TangemSdk.framework/TangemSdk"
BACKUP_PATH="$FRAMEWORK_DIR.backup-$(date +%Y%m%d-%H%M%S)"

echo "🔧 Tangem SDK Binary Patcher"
echo "=============================="

# Step 1: Backup
echo "📦 Creating backup..."
cp -R "$FRAMEWORK_DIR" "$BACKUP_PATH"
echo "✅ Backup saved to: $BACKUP_PATH"

# Step 2: Verify binary
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Binary not found: $BINARY_PATH"
    exit 1
fi

echo "📊 Binary info:"
file "$BINARY_PATH"
ls -lh "$BINARY_PATH"

# Step 3: Apply patch
# TODO: Replace these with actual values from analysis
PATCH_OFFSET=0xABCDEF  # ← To be determined in Step 1
ORIGINAL_BYTES="B4 03 00 54"  # Example: b.ge instruction
PATCH_BYTES="1F 20 03 D5"     # NOP instruction

echo ""
echo "🔍 Verifying patch location..."
echo "Offset: $PATCH_OFFSET"
echo "Expected original bytes: $ORIGINAL_BYTES"

# Read current bytes at offset
CURRENT=$(xxd -s $PATCH_OFFSET -l 4 -p "$BINARY_PATH")
echo "Current bytes: $CURRENT"

# Verify original bytes match
ORIGINAL_HEX=$(echo "$ORIGINAL_BYTES" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
if [ "$CURRENT" != "$ORIGINAL_HEX" ]; then
    echo "⚠️  WARNING: Bytes don't match! Binary may have changed."
    echo "   Expected: $ORIGINAL_HEX"
    echo "   Found:    $CURRENT"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Patch aborted"
        exit 1
    fi
fi

# Apply patch
echo "✏️  Applying patch..."
printf '\x1F\x20\x03\xD5' | dd of="$BINARY_PATH" bs=1 seek=$((PATCH_OFFSET)) count=4 conv=notrunc 2>/dev/null

# Verify patch applied
PATCHED=$(xxd -s $PATCH_OFFSET -l 4 -p "$BINARY_PATH")
echo "Patched bytes: $PATCHED"

# Step 4: Re-sign binary
echo "🔏 Re-signing framework..."
codesign --force --sign - --preserve-metadata=identifier,entitlements "$BINARY_PATH"

echo ""
echo "✅ Patch applied successfully!"
echo ""
echo "Next steps:"
echo "1. Clean build: rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*"
echo "2. Rebuild app in Xcode"
echo "3. Test signing - look for TAG_IsLinked = 01 on 2nd scan"
echo ""
echo "To rollback:"
echo "  rm -rf $FRAMEWORK_DIR"
echo "  cp -R $BACKUP_PATH $FRAMEWORK_DIR"
```

**Script: `scripts/restore-tangem-sdk.sh`**

```bash
#!/bin/bash
set -e

FRAMEWORK_DIR="Multisig/Logic/Tangem/TangemSdk.xcframework"

echo "🔄 Tangem SDK Restore"
echo "===================="

# Find latest backup
LATEST_BACKUP=$(ls -dt "$FRAMEWORK_DIR.backup-"* 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backup found!"
    echo "Searched for: $FRAMEWORK_DIR.backup-*"
    exit 1
fi

echo "📦 Found backup: $LATEST_BACKUP"
read -p "Restore from this backup? (y/n) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Restore cancelled"
    exit 1
fi

# Remove patched version
rm -rf "$FRAMEWORK_DIR"

# Restore backup
cp -R "$LATEST_BACKUP" "$FRAMEWORK_DIR"

echo "✅ Framework restored from backup"
echo ""
echo "Next steps:"
echo "1. Clean build: rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*"
echo "2. Rebuild app in Xcode"
```

---

## Implementation Phases

### Phase 1: Analysis & Preparation (Current)

**1A. Install required tools:**
```bash
brew install binutils  # For objdump if needed
# Hopper Disassembler (optional, $99) or Ghidra (free)
```

**1B. Analyze binary to find patch location:**

Using Hopper Disassembler (recommended):
1. Open `TangemSdk` binary
2. Search for string "Linked terminal feature disabled"
3. Find Xref to this string
4. Navigate to the function
5. Look for firmware version comparison (`cmp` instruction)
6. Note the offset and instruction bytes

Manual method (if no Hopper):
```bash
# Disassemble entire binary (WARNING: Large output)
otool -tV TangemSdk > TangemSdk_disassembly.txt

# Search for our target strings' addresses
# Cross-reference to find the comparison logic
```

**1C. Document patch details:**
- Exact file offset
- Original instruction bytes
- Replacement bytes
- Verification test case

### Phase 2: Create Patch Scripts

**2A. Create `scripts/` directory:**
```bash
mkdir -p scripts
chmod +x scripts/*.sh
```

**2B. Implement `patch-tangem-sdk.sh`** (see script above)

**2C. Implement `restore-tangem-sdk.sh`** (see script above)

**2D. Create test script `scripts/verify-tangem-patch.sh`:**
```bash
#!/bin/bash
BINARY="Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk"
OFFSET=0xABCDEF  # From analysis
EXPECTED="1F2003D5"  # NOP bytes

ACTUAL=$(xxd -s $OFFSET -l 4 -p "$BINARY")
echo "Patch verification:"
echo "  Offset:   $OFFSET"
echo "  Expected: $EXPECTED"
echo "  Actual:   $ACTUAL"

if [ "$ACTUAL" = "$(echo $EXPECTED | tr '[:upper:]' '[:lower:]')" ]; then
    echo "✅ Patch verified!"
    exit 0
else
    echo "❌ Patch not applied or incorrect!"
    exit 1
fi
```

### Phase 3: Apply Patch

**3A. Backup current framework:**
```bash
./scripts/patch-tangem-sdk.sh
```

**3B. Verify patch:**
```bash
./scripts/verify-tangem-patch.sh
```

**3C. Clean build:**
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*
```

**3D. Rebuild in Xcode:**
- Clean Build Folder (Cmd+Shift+K)
- Build (Cmd+B)

### Phase 4: Testing

**Test Case 1: First Scan (Terminal Linking)**
- Expected: 15s delay (card links terminal for first time)
- Look for: `TAG_IsLinked = 00` → card is learning our key
- Result: Signature succeeds

**Test Case 2: Second Scan (Terminal Recognized)**
- Expected: **NO delay**, immediate response
- Look for: `TAG_IsLinked = 01` → card recognizes us
- Result: Signature succeeds in <3 seconds

**Test Case 3: Different Card**
- Expected: 15s delay (new card, needs to link)
- Result: Each card links independently

---

## Fallback Plan: Alternative Approaches

If binary patching proves too difficult:

### Alternative 1: Request Official SDK Update
Contact Tangem support and request they:
- Remove the firmware restriction for `linkedTerminal`
- Or add a config flag to override it

### Alternative 2: Accept the Delay
- Document that HD wallets require multiple scans
- This is actually a **security feature**
- Other apps (official Tangem app) likely use non-HD wallets or have the patched SDK

### Alternative 3: Use Non-HD Wallets Only
- When importing wallets, only use "regular" wallets (not HD)
- The base public key won't require derivation
- Tradeoff: Less flexibility in key management

---

## Next Immediate Steps

**For you to complete Phase 1:**

1. Download **Hopper Disassembler** (free trial): https://www.hopperapp.com/download.html
2. Open the binary:
   ```
   /Users/manuelrm/Documents/GitHub/CTO/safe-ios/Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk
   ```
3. Search for string: `"Linked terminal feature disabled"`
4. Right-click → "References to" → Find the function
5. Look for a pattern like:
   ```assembly
   cmp     w8, #0x434   ; or similar comparison
   b.ge    loc_XXXXX    ; branch if >=
   ```
6. Note the **file offset** and **instruction bytes**

**Then I can:**
- Update the patch script with exact offsets
- Apply the patch
- Test the changes

Would you like me to prepare the patch scripts with placeholder values now, so you can fill in the exact offsets after analyzing the binary? Or would you prefer to try a **source-based rebuild** one more time with better build configuration?

