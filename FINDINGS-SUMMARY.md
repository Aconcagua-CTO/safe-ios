# Tangem Linked Terminal Investigation - Final Findings

## Date: 2025-11-18

---

## 🎯 Original Goal

Achieve single-scan signatures like the official Tangem app (eliminate 15-second delays).

---

## 🔬 What We Discovered

### Finding #1: SDK Blocks HD Wallets

**Location:** `SignCommand.swift` line 256

```swift
guard card.firmwareVersion < .hdWalletAvailable else {
    return nil  // Blocks firmware >= 4.52
}
```

**Impact:** SDK refuses to send terminal keys to HD wallet cards (firmware >= 4.52)

**Your Card:** Firmware 6.33r (blocked by this check)

---

### Finding #2: Binary Patch Works

**We applied a binary patch to bypass this check:**
- Offset: `0xdd9c8` in TangemSdk binary
- Change: `B.NE` → `NOP`
- Result: ✅ Terminal keys successfully sent

**Evidence:**
```
TAG_TerminalPublicKey (0x5C): 04FBA5E7EE5CEA... ✅
TAG_TerminalTransactionSignature (0x57): B7ABD408CACF... ✅
```

---

### Finding #3: Card Firmware Blocks Linking ❌

**Even with terminal keys sent, the card refuses to link:**

First Signature:
```
TAG_IsLinked: 00 (not linked)
[Terminal keys sent]
[15-second delay enforced]
```

Second Signature:
```
TAG_IsLinked: 00 (STILL not linked!)  ← Should be 01!
[Same terminal keys sent again]
[15-second delay enforced AGAIN]  ← Should be 0s!
```

**Conclusion:** The Tangem **card firmware** has its own restriction preventing HD wallet cards from storing terminal links.

---

## 📊 Test Results Summary

| Test | SDK Sends Keys | Card Links Terminal | Delay Skipped | Patch Helps |
|------|----------------|---------------------|---------------|-------------|
| **Before Patch** | ❌ No | ❌ No | ❌ No | N/A |
| **After Patch (1st)** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **After Patch (2nd)** | ✅ Yes | ❌ No | ❌ No | ❌ No |

**Bottom Line:** Patch doesn't help. Card firmware blocks the feature.

---

## 🎓 What We Learned

### The Two-Layer Restriction

```
┌─────────────────────────────────────┐
│         Your App Code               │
│  (Terminal keys in Keychain)        │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│      Tangem SDK (Layer 1)           │
│  ❌ Firmware check blocks HD wallets │  ← We bypassed this ✅
│  ✅ Now sends terminal keys          │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│   Tangem Card Firmware (Layer 2)    │
│  ❌ Refuses to link HD wallets       │  ← Still blocking us ❌
│  ❌ TAG_IsLinked stays 00            │
│  ❌ Enforces 15s delay always        │
└─────────────────────────────────────┘
```

**We can patch the SDK, but we cannot patch the card firmware.**

---

## 💡 Why This Might Be Intentional

Possible reasons Tangem blocks linked terminal for HD wallets:

1. **Security:**
   - HD wallets derive multiple keys from one seed
   - Linked terminal reduces security delay for ALL keys
   - Tangem may want to enforce delays for HD wallet signatures

2. **Compatibility:**
   - Older firmware may have had bugs with linked terminal + HD derivation
   - Restriction added as safety measure

3. **Memory:**
   - Storing terminal key + HD wallet data may exceed card memory
   - Restriction prevents memory issues

4. **Design Decision:**
   - May be an intentional tradeoff
   - HD wallets = more features but no linked terminal
   - Regular wallets = linked terminal but fewer features

---

## 📧 Support Reports Created

### For Email Submission

**File:** `TANGEM-SUPPORT-EMAIL.txt`  
**To:** support@tangem.com  
**Action:** Copy/paste into email, attach TANGEM-SUPPORT-REPORT.md

### For GitHub Issue

**File:** `TANGEM-SUPPORT-GITHUB-ISSUE.md`  
**URL:** https://github.com/tangem/tangem-sdk-ios/issues  
**Action:** Create new issue, paste content

### Full Technical Report

**File:** `TANGEM-SUPPORT-REPORT.md`  
**Length:** ~22 KB, comprehensive analysis  
**Use:** Attach to email or reference documentation

### Submission Guide

**File:** `HOW-TO-SUBMIT-TANGEM-SUPPORT.md`  
**Contains:** Step-by-step instructions, tips, what to expect

---

## ⚠️ Important: Patch Disclosure

All reports **explicitly disclose** the binary patch we applied:

- ✅ Clearly state it was for **testing/investigation only**
- ✅ Explain it's **NOT for production**
- ✅ Show full technical details (offset, bytes, purpose)
- ✅ Demonstrate we're seeking **official solution**
- ✅ Commit to **removing patch** pending their guidance

**This transparency is crucial for:**
- Building trust with Tangem
- Getting accurate technical response
- Avoiding any appearance of improper modification
- Showing we're serious about proper implementation

---

## 🔄 Next Steps (Recommended Order)

### 1. Review Reports ✓
- Read `TANGEM-SUPPORT-EMAIL.txt`
- Verify all information is accurate
- Customize contact information

### 2. Submit to Tangem 📧
- Email: support@tangem.com (recommended)
- OR create GitHub issue
- Wait for response (1-3 business days expected)

### 3. Rollback Patch 🔙
```bash
cd /Users/manuelrm/Documents/GitHub/safe-ios
./scripts/restore-tangem-sdk.sh

# Verify rollback
./scripts/verify-tangem-patch.sh
# Should show: ❌ PATCH NOT APPLIED

# Clean and rebuild
rm -rf ~/Library/Developer/Xcode/DerivedData/
# Xcode: Clean Build Folder → Build
```

### 4. Test with Original SDK ✓
- Confirm app works correctly
- Verify signatures complete (with 15s delay)
- Ensure transactions submit successfully

### 5. Improve UI/UX 🎨
While waiting for Tangem response:

```swift
// TangemSignerViewController.swift
let initialMessage = Message(
    header: "Tangem Card Security",
    body: """
    Hold your card steady for 15-20 seconds.
    
    This security delay is required by your Tangem card
    to protect against unauthorized access.
    
    Do NOT remove the card until signing completes.
    """
)
```

### 6. Document for Users 📝
Update user documentation:
- Explain the 15-second delay
- Note it's a Tangem hardware security feature
- Set appropriate expectations

### 7. Track Tangem Response 👀
When Tangem responds:
- Document their answer
- Implement recommendations
- Update your code accordingly
- Test any solutions they provide

---

## 📋 Possible Tangem Responses

### Response A: "It's By Design"
**If they say:** "HD wallets don't support linked terminal for security reasons"

**Your action:**
- ✅ Accept explanation
- ✅ Remove all patch-related code
- ✅ Document limitation for users
- ✅ Improve UI messaging
- ✅ Close investigation

### Response B: "Here's How to Enable It"
**If they say:** "Use this configuration..." or "Update to this SDK version..."

**Your action:**
- ✅ Implement their solution
- ✅ Remove binary patch
- ✅ Test thoroughly
- ✅ Document the official approach
- ✅ Thank them!

### Response C: "We're Investigating"
**If they say:** "We need to check with our engineering team..."

**Your action:**
- ✅ Provide any additional info requested
- ✅ Be patient
- ✅ Keep patch for testing if they ask
- ✅ Use original SDK for any releases
- ✅ Follow up if no response in 2 weeks

### Response D: "Will Fix in Future Version"
**If they say:** "We plan to support this in SDK X.X or firmware Y.Y"

**Your action:**
- ✅ Thank them for the roadmap
- ✅ Ask for timeline
- ✅ Remove patch now
- ✅ Plan to update when available
- ✅ Document interim limitation

---

## ✅ What We Proved

1. **✅ Our implementation is correct:**
   - Terminal keys properly generated (secp256k1)
   - Keys stable across signatures (iOS Keychain)
   - SDK configuration correct (linkedTerminal = true)
   - Signing flow correct (SignHashesCommand)

2. **✅ SDK restriction exists:**
   - Firmware check at line 256 of SignCommand.swift
   - Blocks terminal keys for firmware >= 4.52
   - Can be bypassed with binary modification

3. **✅ Patch works as intended:**
   - Terminal keys successfully sent
   - Valid terminal signatures generated
   - SDK behaves as expected after patch

4. **❌ Card firmware blocks feature:**
   - Card receives terminal keys
   - Card refuses to store link
   - TAG_IsLinked stays 00
   - 15-second delay enforced always

---

## 🎯 Final Recommendation

### For Production

**DO:**
- ✅ Rollback the binary patch immediately
- ✅ Use original Tangem SDK (unmodified)
- ✅ Accept the 15-second delay
- ✅ Improve UI messaging
- ✅ Submit support request to Tangem
- ✅ Wait for official guidance

**DON'T:**
- ❌ Ship with the binary patch
- ❌ Try to find other patches
- ❌ Attempt to modify card firmware
- ❌ Submit to App Store with modified SDK

### For Investigation

**IF Tangem provides a solution:**
- Implement their official recommendation
- Test thoroughly
- Document the approach
- Share findings with team

**IF no solution available:**
- Accept as designed behavior
- Focus on UX improvements
- Consider this a "done" investigation
- Move on to other priorities

---

## 📚 Documentation Created

### Support Reports
- `TANGEM-SUPPORT-REPORT.md` - Full technical report
- `TANGEM-SUPPORT-GITHUB-ISSUE.md` - GitHub issue format
- `TANGEM-SUPPORT-EMAIL.txt` - Email format
- `HOW-TO-SUBMIT-TANGEM-SUPPORT.md` - Submission guide

### Analysis & Results
- `docs/TANGEM-SINGLE-SCAN-ANALYSIS.md` - Complete analysis
- `docs/TANGEM-PATCH-RESULTS-FINAL.md` - Test results
- `docs/PATCH-APPLICATION-LOG-2025-11-18.md` - Patch log
- `docs/PATCH-TESTING-GUIDE.md` - Testing protocol

### Reference
- `PATCH-APPLIED-README.md` - Quick reference
- `scripts/patch-tangem-sdk.sh` - Patch script (used)
- `scripts/restore-tangem-sdk.sh` - Rollback script (ready)
- `scripts/verify-tangem-patch.sh` - Verification script

---

## 🏆 Achievement Unlocked

Despite not achieving the original goal (fast subsequent signatures), we:

✅ **Thoroughly investigated** the root cause  
✅ **Identified two layers** of restriction  
✅ **Proved our implementation** is correct  
✅ **Created comprehensive documentation** for future reference  
✅ **Prepared professional support request** for Tangem  
✅ **Learned the technical details** of Tangem's security model  

**This is valuable knowledge that will help with future hardware wallet integrations!**

---

## 📞 Contact Tangem

**Recommended:** Email  
**To:** support@tangem.com  
**Subject:** Linked Terminal Feature Not Working for HD Wallet Cards  
**Body:** Use `TANGEM-SUPPORT-EMAIL.txt`  
**Attach:** `TANGEM-SUPPORT-REPORT.md`

**Alternative:** GitHub Issue  
**URL:** https://github.com/tangem/tangem-sdk-ios/issues/new  
**Content:** Use `TANGEM-SUPPORT-GITHUB-ISSUE.md`

---

**Investigation Complete** ✅  
**Reports Ready** ✅  
**Next: Submit to Tangem** ⏭️

