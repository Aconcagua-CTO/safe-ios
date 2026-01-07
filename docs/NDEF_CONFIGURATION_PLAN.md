# NDEF Configuration Plan - Using cfg_ndef with flagUseText

## Background

ARX support has confirmed that the correct command to replace the NDEF URL is:
- **Command**: `cfg_ndef` (command code `0x04`)
- **Flag**: `flagUseText` - This flag tells the card to use a static text/URL instead of generating dynamic URLs

## Current Understanding

### Command Structure
- **Command Code**: `0x04` (CFG_NDEF)
- **APDU Structure**: Uses the existing HaLo core command format:
  - CLA: `0xB0`
  - INS: `0x51`
  - P1: `0x00`
  - P2: `0x00`
  - Lc: Payload length
  - Data: `[0x04] + [flags] + [NDEF data or URL]`
  - Le: `0x00`

### Key Findings from Investigation
1. Command `0x04` exists (returns `ERROR_CODE_INVALID_LENGTH` instead of `ERROR_CODE_UNKNOWN_CMD`)
2. All tested payload formats failed with `INVALID_LENGTH`
3. The missing piece is the `flagUseText` flag structure

## Implementation Plan

### Phase 1: Research flagUseText Structure ✅ COMPLETED
**Findings:**
1. ✅ Accessed libhalo GitHub repository documentation
   - URL: https://github.com/arx-research/libhalo/blob/master/docs/halo-command-set.md#command-cfg_ndef
   - `cfg_ndef` command takes boolean flags as JSON parameters
   - `flagUseText` (bool) - whether to use text NDEF record instead of URL record
   - Documentation shows high-level API format, not low-level APDU format

2. **Key Discovery:**
   - The documentation shows `cfg_ndef` as a high-level command with boolean flags
   - However, we need the low-level APDU format (command code 0x04)
   - The flags need to be encoded as bytes in the payload
   - **Question**: How is the static text/URL value set? Is it from graffiti, latch, or separate parameter?

3. **Flag Structure Findings:**
   - ✅ Documentation shows 15+ boolean flags for `cfg_ndef`:
     - `flagUseText` (bool) - use text NDEF record instead of URL
     - `flagHidePk1`, `flagHidePk2`, `flagHidePk3` (bool) - hide public keys
     - `flagShowPk1Attest`, `flagShowPk2Attest`, `flagShowPk3Attest` (bool) - show attest signatures
     - `flagShowLatch1Sig`, `flagShowLatch2Sig` (bool) - show latch signatures
     - `flagHideRNDSIG`, `flagHideCMDRES` (bool) - hide random sig and command response
     - `flagLegacyStatic` (bool) - use legacy static format
     - `flagShowPkN`, `flagShowPkNAttest` (bool) - show additional key
     - `flagRNDSIGUseBJJ62` (bool) - use key slot 0x62
     - `pkN` (number) - optional key slot number
   - Flags are likely encoded as a multi-byte bitmask (2-3 bytes for 15+ flags)
   - `flagUseText = true` is likely bit 0 of the first byte (0x01)
   - **Key Discovery**: When `flagUseText = true`, the text comes from the graffiti slot (stored via `store_graffiti`)
   - Payload format: `[0x04] [flags_bytes...] [pkN?]` (text is NOT in payload, it's from graffiti)

### Phase 2: Implement cfg_ndef with flagUseText
**Tasks:**
1. **Research how static text is set:**
   - Check if text comes from `store_graffiti` command
   - Check if text is set via separate parameter in cfg_ndef
   - Check libhalo source code for actual implementation

2. **Create new method `configureNDEFWithFlagUseText(url: String)`**
   - Replace the experimental `configureNDEFBaseURL()` method
   - Use command code `0x04`
   - Encode boolean flags as bitmask byte(s)
   - Include text/URL value in payload

3. **Flag Encoding Strategy (Updated):**
   - **Primary Hypothesis**: Multi-byte flags structure (2-3 bytes)
     - Byte 0, Bit 0 (0x01) = flagUseText
     - Byte 0, Bit 1 (0x02) = flagHidePk1
     - Byte 0, Bit 2 (0x04) = flagHidePk2
     - Byte 0, Bit 3 (0x08) = flagHidePk3
     - Byte 0, Bit 4 (0x10) = flagShowPk1Attest
     - Byte 0, Bit 5 (0x20) = flagShowPk2Attest
     - Byte 0, Bit 6 (0x40) = flagShowPk3Attest
     - Byte 0, Bit 7 (0x80) = flagShowLatch1Sig
     - Byte 1, Bit 0 (0x01) = flagShowLatch2Sig
     - Byte 1, Bit 1 (0x02) = flagHideRNDSIG
     - Byte 1, Bit 2 (0x04) = flagHideCMDRES
     - Byte 1, Bit 3 (0x08) = flagLegacyStatic
     - Byte 1, Bit 4 (0x10) = flagShowPkN
     - Byte 1, Bit 5 (0x20) = flagShowPkNAttest
     - Byte 1, Bit 6 (0x40) = flagRNDSIGUseBJJ62
     - Byte 2 or pkN parameter for key slot number
   - **Testing Strategy**: Try multiple flag structures:
     - Single byte: `[0x04, 0x01]` (just flagUseText)
     - Two bytes: `[0x04, 0x01, 0x00]` (flagUseText + padding)
     - Three bytes: `[0x04, 0x01, 0x00, 0x00]` (flagUseText + 2 bytes padding)
     - With pkN: `[0x04, 0x01, 0x00, 0x01]` (flagUseText + pkN=1)

4. **Test different payload formats:**
   - **Format 1**: `[0x04, 0x01]` (just flagUseText, text from graffiti?)
   - **Format 2**: `[0x04, 0x01, urlLength, urlBytes]` (flag + URL)
   - **Format 3**: `[0x04, flagsByte, textLength, textBytes]` (flags + text)
   - **Format 4**: `[0x04, flagsByte, ndefMessageBytes]` (flags + full NDEF)

### Phase 3: Testing and Verification
**Tasks:**
1. Test each flag format
2. Verify by reading back NDEF after write
3. Check if card stops generating dynamic URLs
4. Confirm static URL is used

## Implementation Details

### Current Code Location
- File: `Multisig/Logic/Burner/BurnerService.swift`
- Method: `configureNDEFBaseURL(url:)` (lines ~637-784)
- Should be replaced with: `configureNDEFWithFlagUseText(url:)`

### Expected Payload Structure (Hypothesis)
Based on common flag patterns, the payload might be:
```
[0x04] [flagUseText_byte] [url_length?] [url_bytes]
```

Or with full NDEF message:
```
[0x04] [flagUseText_byte] [ndef_message_bytes]
```

### Solution Approach

Based on the documentation, the solution likely involves **two commands**:

### Step 1: Store the static text/URL using `store_graffiti`
- **Purpose**: Store the text/URL value in the rewritable static string slot
- **Limitations**: 
  - Max 32 ASCII characters
  - Supported charset: `A-Z`, `a-z`, `0-9`, `-_.`
  - "www.boveda.ai" = 13 characters ✅ (fits within limit)
- **Command**: `store_graffiti` (need to find command code)
- **Payload**: `[slotNo] [data_length] [data_bytes]` or similar

### Step 2: Configure NDEF to use text with `cfg_ndef`
- **Purpose**: Tell the card to use the graffiti text instead of generating dynamic URLs
- **Command**: `cfg_ndef` (command code `0x04`)
- **Flag**: Set `flagUseText = true` (bit 0 = 0x01 in flags byte)
- **Payload**: `[0x04] [flags_byte]` where flags_byte has bit 0 set for flagUseText

## Next Steps
1. **Immediate**: Find command code for `store_graffiti` 
2. **Short-term**: Implement both `store_graffiti` and `cfg_ndef` with flagUseText
3. **Testing**: 
   - Store "www.boveda.ai" in graffiti
   - Set flagUseText = true
   - Verify card uses static text instead of dynamic URL
4. **Cleanup**: Remove experimental code once working solution is found

## References
- libhalo Documentation: https://github.com/arx-research/libhalo/blob/master/docs/halo-command-set.md#command-cfg_ndef
- ARX Support: Confirmed `cfg_ndef` with `flagUseText` is the correct approach
- Current Implementation: `Multisig/Logic/Burner/BurnerService.swift`

## Notes
- Command `0x04` is confirmed to exist (we've been getting `INVALID_LENGTH` errors)
- The `flagUseText` flag is the key missing piece
- Once we have the exact flag structure, implementation should be straightforward

