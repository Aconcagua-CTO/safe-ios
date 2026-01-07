# How to Submit Tangem Support Request

## 📋 Documents Prepared

I've created 3 formats of the same information for different submission methods:

### 1. **TANGEM-SUPPORT-REPORT.md** (Most Comprehensive)
- **Use for:** Email attachment or detailed documentation
- **Format:** Full markdown with all technical details
- **Length:** ~500 lines with complete logs and analysis
- **Best for:** Thorough technical review

### 2. **TANGEM-SUPPORT-GITHUB-ISSUE.md** (GitHub Format)
- **Use for:** Creating a GitHub issue
- **Format:** Structured for GitHub issue tracker
- **Length:** ~350 lines, well-organized sections
- **Best for:** Public discussion and tracking

### 3. **TANGEM-SUPPORT-EMAIL.txt** (Email-Friendly)
- **Use for:** Direct email to support
- **Format:** Plain text, easy to copy/paste
- **Length:** ~200 lines, concise but complete
- **Best for:** Quick submission via email

---

## 📧 Submission Options

### Option A: Email to Tangem Support (Recommended)

**To:** support@tangem.com  
**Subject:** Linked Terminal Feature Not Working for HD Wallet Cards

**Steps:**
1. Copy contents of `TANGEM-SUPPORT-EMAIL.txt`
2. Paste into email body
3. Attach `TANGEM-SUPPORT-REPORT.md` for full details
4. Add your contact information at the bottom
5. Send!

**Expected Response Time:** 1-3 business days

---

### Option B: GitHub Issue

**Repository:** https://github.com/tangem/tangem-sdk-ios/issues

**Steps:**
1. Go to: https://github.com/tangem/tangem-sdk-ios/issues/new
2. Title: `Linked Terminal not working for HD Wallet cards (firmware >= 4.52)`
3. Copy contents of `TANGEM-SUPPORT-GITHUB-ISSUE.md`
4. Paste into issue description
5. Add labels: `question`, `enhancement`, or `bug` (as appropriate)
6. Submit!

**Benefits:**
- Public discussion
- Community input
- Trackable issue number
- May help other developers

**Drawbacks:**
- Public (your implementation details visible)
- May take longer for response

---

### Option C: Developer Portal / Forum

**If Tangem has a developer portal:**
1. Log in to developer portal
2. Create new support ticket
3. Use `TANGEM-SUPPORT-REPORT.md` content
4. Attach logs if requested

---

## 🎯 Key Points to Emphasize

When submitting, make sure to highlight:

### 1. We Applied a Binary Patch (Be Transparent)
**Important:** Clearly state this was for **testing/investigation only**, NOT for production.

Say:
> "To investigate the root cause, we applied a binary patch to bypass the SDK's firmware check (development environment only). This confirmed that terminal keys are properly sent, but the card firmware itself rejects the link."

### 2. We're Seeking Official Guidance
Make it clear you want to do things the "right way":

> "We are NOT planning to ship the patched SDK to production. We're seeking your official recommendation for achieving better signing performance with HD wallet cards."

### 3. We've Done Our Homework
Show that you've investigated thoroughly:

> "We analyzed both the SDK source code and the official Tangem iOS app repository. We implemented terminal key management following SDK patterns. We tested extensively with detailed logging."

### 4. We're Flexible
Emphasize willingness to adapt:

> "If the 15-second delay is by design for HD wallets, we'll accept it and improve our UI/UX accordingly. We're seeking clarification, not demanding a change."

---

## 📊 What to Include

### Essential Information

✅ **Card Details:**
- Card ID: AF05000000203703
- Firmware: 6.33r
- Type: HD Wallet

✅ **Problem Statement:**
- TAG_IsLinked stays 00
- 15-second delay on every signature
- Terminal keys sent but not accepted

✅ **What We Tried:**
- Binary patch to bypass SDK check
- Terminal keys properly implemented
- Tested twice to confirm behavior

✅ **Logs:**
- TAG_TerminalPublicKey sent
- TAG_TerminalTransactionSignature sent
- TAG_IsLinked remains 00
- Full 15-second delays

✅ **Question:**
- Is this intentional?
- Can it be enabled?
- What do you recommend?

---

## 🚫 What NOT to Say

❌ Don't demand they fix it:
- "You MUST enable this feature"
- "This is a bug that needs to be fixed immediately"

✅ Instead ask for clarification:
- "Is this intentional behavior?"
- "What do you recommend for our use case?"

❌ Don't criticize their design:
- "This limitation makes no sense"
- "Your SDK is broken"

✅ Instead seek understanding:
- "We'd like to understand the reasoning"
- "Is there a security concern we should know about?"

❌ Don't mention App Store submission with patch:
- (You're not doing this anyway, but don't even hint at it)

✅ Do emphasize testing only:
- "Development environment only"
- "For investigation purposes"
- "Will rollback before production"

---

## ⏱️ Expected Outcomes

### Best Case
Tangem responds with:
- "Here's how to enable it for HD wallets: [config flag]"
- "We'll remove the restriction in SDK version X.X"
- "Use this firmware update for your card"

### Likely Case
Tangem responds with:
- "The restriction is intentional for security"
- "HD wallets don't support linked terminal"
- "We recommend [alternative approach]"

### Response to Each

**If they have a solution:**
- Thank them
- Implement their recommendation
- Test and report back
- Remove your binary patch

**If it's by design:**
- Thank them for clarification
- Remove your binary patch immediately
- Accept the 15-second delay
- Improve UI messaging
- Document limitation for users

**If they're investigating:**
- Provide any additional info requested
- Wait for their analysis
- Keep patch for testing if they ask
- Be patient and collaborative

---

## 📝 Template Customization

Before sending, customize these sections:

### In TANGEM-SUPPORT-EMAIL.txt:

**Line: "Contact: [Your email]"**
- Replace with your actual email

**Line: "Organization: [Your organization]"**
- Replace with your company/project name

### In TANGEM-SUPPORT-REPORT.md:

**Section: "Contact Information"**
- Add your actual contact details

### In TANGEM-SUPPORT-GITHUB-ISSUE.md:

**Bottom of issue:**
- Add your GitHub username
- Link to your repository (if public)

---

## 🔄 After Submitting

### 1. Rollback the Patch
```bash
cd /Users/manuelrm/Documents/GitHub/CTO/safe-ios
./scripts/restore-tangem-sdk.sh

# Clean and rebuild
rm -rf ~/Library/Developer/Xcode/DerivedData/
# In Xcode: Product → Clean Build Folder
# In Xcode: Product → Build
```

### 2. Verify Rollback
```bash
./scripts/verify-tangem-patch.sh
# Should show: ❌ PATCH NOT APPLIED
```

### 3. Test with Original SDK
- Make sure app still works
- Confirm signatures complete (with 15s delay)
- Verify transactions submit successfully

### 4. Document Interim Solution
- Update user documentation
- Explain the 15-second delay
- Set expectations appropriately

### 5. Track Tangem's Response
- Save their email/issue response
- Update your documentation
- Implement their recommendations
- Test any solutions they provide

---

## 📎 Quick Reference

### Files Created for Tangem

| File | Purpose | Best For |
|------|---------|----------|
| `TANGEM-SUPPORT-REPORT.md` | Complete technical report | Email attachment |
| `TANGEM-SUPPORT-GITHUB-ISSUE.md` | GitHub issue format | Public issue tracker |
| `TANGEM-SUPPORT-EMAIL.txt` | Plain text email | Direct email |
| `docs/TANGEM-PATCH-RESULTS-FINAL.md` | Test results summary | Internal reference |

### Files to Reference

| File | Contains |
|------|----------|
| `docs/TANGEM-SINGLE-SCAN-ANALYSIS.md` | Original analysis |
| `docs/PATCH-APPLICATION-LOG-2025-11-18.md` | Patch details |
| `docs/PATCH-TESTING-GUIDE.md` | Testing protocol |

---

## 🎯 Success Metrics

Your support request is good if it:

✅ Clearly explains the problem  
✅ Shows what you've tried  
✅ Includes relevant logs  
✅ **Transparently discloses the binary patch**  
✅ Asks specific questions  
✅ Shows willingness to adapt  
✅ Provides all technical details they might need

---

## 💡 Tips for Best Results

1. **Be Professional:** Respectful, clear, technical
2. **Be Transparent:** Fully disclose the patch
3. **Be Patient:** Give them time to investigate
4. **Be Collaborative:** Willing to test solutions
5. **Be Grateful:** Thank them for their time

---

**Remember:** Tangem builds excellent hardware wallets. This may be a feature limitation by design, not a bug. Be respectful of their engineering decisions!

Good luck! 🍀

