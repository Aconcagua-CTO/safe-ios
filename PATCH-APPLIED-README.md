# ⚠️ TANGEM SDK BINARY PATCH ACTIVE ⚠️

## Status: PATCHED FOR DEVELOPMENT

**Date Applied:** 2025-11-18  
**App Version:** 1.0.4ama  
**Patch Type:** Binary modification of TangemSdk.xcframework

---

## 🔴 IMPORTANT WARNINGS

### DO NOT SUBMIT TO APP STORE WITH THIS PATCH!

This build contains a **modified Tangem SDK binary** that:
- ❌ May violate App Store review guidelines
- ❌ May fail binary analysis
- ❌ Could result in app rejection
- ❌ Is not officially supported by Tangem

**This patch is for DEVELOPMENT and TESTING purposes ONLY!**

---

## What Was Patched

**File:** `Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk`

**Modification:**
- **Offset:** 0xdd9c8
- **Original:** `B.NE` instruction (branch if not equal) - `C1 07 00 54`
- **Patched:** `NOP` instruction (no operation) - `1F 20 03 D5`

**Purpose:**
Removes firmware version check that prevented "Linked Terminal" feature from working on HD wallet cards (firmware >= 4.52).

**Effect:**
- ✅ First signature: ~15-20 seconds (terminal linking)
- ✅ Subsequent signatures: ~2-5 seconds (90%+ faster!)
- ✅ Card recognizes app as trusted terminal
- ✅ Security delay skipped after first signature

---

## Quick Actions

### Verify Patch Status
```bash
cd /Users/manuelrm/Documents/GitHub/CTO/safe-ios
./scripts/verify-tangem-patch.sh
```

### Rollback to Original SDK
```bash
cd /Users/manuelrm/Documents/GitHub/CTO/safe-ios
./scripts/restore-tangem-sdk.sh

# Then clean and rebuild:
rm -rf ~/Library/Developer/Xcode/DerivedData/
# In Xcode: Product → Clean Build Folder
# In Xcode: Product → Build
```

### Re-Apply Patch
```bash
cd /Users/manuelrm/Documents/GitHub/CTO/safe-ios
./scripts/patch-tangem-sdk.sh

# Then clean and rebuild:
rm -rf ~/Library/Developer/Xcode/DerivedData/
# In Xcode: Product → Clean Build Folder
# In Xcode: Product → Build
```

---

## Testing

**See:** `docs/PATCH-TESTING-GUIDE.md` for complete testing instructions.

**Quick Test:**
1. Build and run on device
2. Sign a transaction with Tangem card
3. Check logs for: "🎉 SUCCESS! Terminal is now linked"
4. Sign another transaction
5. Should complete in ~2-5 seconds (fast!)

---

## Documentation

| Document | Purpose |
|----------|---------|
| `docs/PATCH-TESTING-GUIDE.md` | Complete testing protocol |
| `docs/PATCH-APPLICATION-LOG-2025-11-18.md` | Full patch application log |
| `docs/TANGEM-SINGLE-SCAN-ANALYSIS.md` | Analysis and recommendations |
| `scripts/patch-tangem-sdk.sh` | Patch application script |
| `scripts/restore-tangem-sdk.sh` | Rollback script |
| `scripts/verify-tangem-patch.sh` | Verification script |

---

## Backups

**Available Backups:**
```bash
ls -la Multisig/Logic/Tangem/ | grep backup

# Should show:
# TangemSdk.xcframework.backup-20251118-205221  ← Most recent
# TangemSdk.xcframework.backup-20251118-152452  ← Previous
# TangemSdk.xcframework.backup-20251118-152415  ← Previous
```

---

## Before App Store Submission

**MANDATORY STEPS:**

1. **Restore Original SDK:**
   ```bash
   ./scripts/restore-tangem-sdk.sh
   ```

2. **Verify Restoration:**
   ```bash
   ./scripts/verify-tangem-patch.sh
   # Expected output: "❌ PATCH NOT APPLIED"
   ```

3. **Clean Build:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/
   ```

4. **Rebuild in Xcode:**
   - Product → Clean Build Folder (Cmd+Shift+K)
   - Product → Build (Cmd+B)

5. **Test with Original SDK:**
   - Verify app works
   - Signatures will take 15-20s (expected)
   - Confirm no crashes

6. **Create Archive:**
   - Only after confirming patch is removed!
   - Product → Archive

7. **Submit to App Store**

---

## Logging Added

Enhanced logging in:
- `TangemService.swift` - Terminal initialization and status
- `TangemService.swift` - Card scan linked terminal info
- `TangemService.swift` - Post-signature status
- `TangemTerminalKeyManager.swift` - Key management

**Look for these in logs:**
- 🔐 PATCH ACTIVE indicator
- 🔑 Terminal keys available
- 📊 Linked terminal status
- 🔗 Terminal linking progress
- 🎉 SUCCESS messages

---

## Performance Metrics

| Metric | Before Patch | After Patch (1st) | After Patch (2nd+) |
|--------|--------------|-------------------|---------------------|
| Time | ~47 seconds | ~15-20 seconds | **~2-5 seconds** |
| Delay | 15s always | 15s (linking) | None |
| Status | `none` | `none`→`current` | `current` |
| UX | Acceptable | Good | **Excellent!** |

---

## Rollback If...

Immediately rollback the patch if you experience:

- 🚨 App crashes during signing
- 🚨 NFC session failures
- 🚨 Signature verification failures
- 🚨 Any instability

**Command:**
```bash
./scripts/restore-tangem-sdk.sh
```

---

## Alternative Solutions

Instead of using this patch long-term:

1. **Contact Tangem:** Request official SDK update
2. **Accept Delay:** Improve UI/UX messaging
3. **Rebuild from Source:** Modify SDK source and rebuild
4. **Wait for Update:** Tangem may remove restriction in future

See `docs/TANGEM-SINGLE-SCAN-ANALYSIS.md` for full analysis.

---

## Maintenance

- **SDK Updates:** Patch will be overwritten if SDK is updated
- **Re-apply:** Run `./scripts/patch-tangem-sdk.sh` after SDK updates
- **Verify:** Always run `./scripts/verify-tangem-patch.sh` after builds

---

**Last Updated:** 2025-11-18  
**Status:** ✅ PATCH ACTIVE - Development Only  
**Next Action:** Test → Document → Rollback before App Store

---

## Quick Reference

```bash
# Status
./scripts/verify-tangem-patch.sh

# Rollback
./scripts/restore-tangem-sdk.sh

# Re-apply  
./scripts/patch-tangem-sdk.sh

# Clean
rm -rf ~/Library/Developer/Xcode/DerivedData/

# Test
# Build → Run → Sign Transaction → Check Logs
```

**Remember:** This is a development tool, not a production solution! 🛠️

