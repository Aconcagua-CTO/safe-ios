# Swift 6 Migration Guide

**Date:** October 28, 2025  
**Migration:** Swift 5.0 → Swift 6.2  
**Status:** ✅ Completed Successfully

## Overview

This document details the migration of the Safe iOS app from Swift 5.0 to Swift 6.2. The migration was necessary because the development environment (macOS 26.0.1, Xcode 26.0.1) ships with Swift 6.2 and cannot run older Swift versions.

## Environment

- **macOS Version:** 26.0.1 (Build 25A362)
- **Xcode Version:** 26.0.1 (Build 17A400)
- **Swift Version:** 6.2 (swiftlang-6.2.0.19.9)
- **Previous Swift Version (Project):** 5.0
- **Project Configuration:** `SWIFT_VERSION = 5.0` (not updated yet)

## Executive Summary

**Total Fixes:** 30+ Swift 6 compatibility issues resolved

### Issue Categories:
1. **RawSpan Type Errors** (20+ fixes) - Critical compilation blockers
2. **Access Control Syntax** (9 fixes) - `private (set)` spacing
3. **Type Ambiguity** (2 fixes) - Module name conflicts
4. **Import Issues** (1 fix) - Circular imports

---

## 1. RawSpan Type Errors

### The Problem

Swift 6 introduced `RawSpan` - a new non-copyable, read-only type for better performance and memory safety. The `Data.bytes` property now returns `RawSpan` instead of `[UInt8]`, which breaks code that expects:
- `.count`, `.last`, `.first` properties
- Subscript access `[index]`
- Mutable operations
- Type compatibility with `[UInt8]`/`Bytes`

### The Solution

**Before (Swift 5):**
```swift
let bytes = data.bytes                    // Returns [UInt8]
let count = data.bytes.count              // Works
let first = data.bytes[0]                 // Works
```

**After (Swift 6 - Broken):**
```swift
let bytes = data.bytes                    // Returns RawSpan
let count = data.bytes.count              // ❌ Error: no member 'count'
let first = data.bytes[0]                 // ❌ Error: no subscript
```

**Fixed (Swift 6 - Working):**
```swift
let bytes = [UInt8](data)                 // Direct conversion
let count = bytes.count                   // ✅ Works
let first = bytes[0]                      // ✅ Works
```

### Files Fixed (20+ instances)

#### WebConnectionController.swift (2 fixes)
- **Lines 1118, 1178:** Signature byte manipulation
```swift
// Before
var signatureBytes = Array(Foundation.Data(hex: signature).bytes)

// After
var signatureBytes = [UInt8](Foundation.Data(hex: signature))
```

#### SignatureRequestViewController.swift (1 fix)
- **Line 192:** Message signing with private key
```swift
// Before
let signatureParts = try pk._store.sign(message: [UInt8](preimage.bytes))

// After
let signatureParts = try pk._store.sign(message: [UInt8](preimage))
```

#### ImportExportDataController.swift (1 fix + variable shadowing)
- **Line 161:** PBKDF key derivation
```swift
// Before (with shadowing issue)
func deriveKey(from plaintext: String, salt: Data, rounds: Int) -> Data? {
    var salt = Array(salt.bytes)  // Shadows parameter, causes ambiguity

// After
func deriveKey(from plaintext: String, salt: Data, rounds: Int) -> Data? {
    var saltBytes: [UInt8] = [UInt8](salt)  // Explicit type, no shadowing
```

#### BIP32HDNode.swift (11 fixes)
The most affected file due to heavy cryptographic operations:

1. **Lines 77, 79:** Array subscript and UInt32 initialization
2. **Lines 104, 105:** HMAC key and seed conversion
3. **Lines 114, 179, 230, 233:** Public key validation (first byte checks)
4. **Lines 140, 145, 150, 154, 209, 213:** HMAC authenticate operations
5. **Line 279:** Base58 encoding

```swift
// Before
let hmac = HMAC(key: Array(hmacKey.bytes), variant: .sha512)
guard let entropy = try? hmac.authenticate(Array(seed.bytes))

// After
let hmac = HMAC(key: [UInt8](hmacKey), variant: .sha512)
guard let entropy = try? hmac.authenticate([UInt8](seed))
```

#### TransactionDetailsViewController.swift (1 fix)
- **Line 598:** ECDSA signature validation
```swift
// Before
let lastByte = Array($0.signature.data.bytes).last ?? 0

// After
let lastByte = [UInt8]($0.signature.data).last ?? 0
```

#### TransactionExecutionController.swift (1 fix)
- **Line 496:** Public key recovery from signature
```swift
// Before
message: Array(preimage.bytes)

// After
message: [UInt8](preimage)
```

### Key Pattern: Direct Conversion

**Always use direct conversion instead of `.bytes`:**

```swift
✅ [UInt8](data)           // Correct - bypasses RawSpan
❌ Array(data.bytes)       // Broken - RawSpan issues
❌ [UInt8](data.bytes)     // Broken - class constraint error
```

---

## 2. Access Control Syntax Errors

### The Problem

Swift 6 language mode enforces stricter syntax rules. Whitespace between `private` and `(set)` is now an error.

### The Solution

**Before (Swift 5 - allowed):**
```swift
private (set) var myProperty: String
```

**After (Swift 6 - required):**
```swift
private(set) var myProperty: String
```

### Files Fixed (9 instances)

1. **ClaimTokensViewController.swift** (4 fixes)
   - Lines 24, 25, 31, 34
   
2. **TransactionDetailCellBuilder.swift** (2 fixes)
   - Lines 19, 20

3. **ContainerViewController.swift** (1 fix)
   - Line 18

4. **TokenAmountField.swift** (1 fix)
   - Line 15

5. **NetworkStatusObserver.swift** (1 fix)
   - Line 41

6. **LogService.swift** (1 fix)
   - Line 105

---

## 3. Type Ambiguity Errors

### The Problem

Swift 6 has stricter type resolution. When multiple types with the same name exist (e.g., `Foundation.Data` and `EthRpc1.Data`), the compiler can't infer which one to use, especially with extensions.

### The Solution

Explicitly qualify the type with its module name.

**Before:**
```swift
import Foundation
import Ethereum  // Contains EthRpc1.Data

var signatureBytes = [UInt8](Data(hex: signature))
// Compiler confused: Foundation.Data or EthRpc1.Data?
```

**After:**
```swift
var signatureBytes = [UInt8](Foundation.Data(hex: signature))
// Explicit: use Foundation.Data
```

### Files Fixed

- **WebConnectionController.swift** (2 instances, lines 1118, 1178)

### Error Message Pattern

These errors often manifest with confusing messages like:
```
Cannot convert value of type 'RawSpan' to expected argument type 'Eth.AccessList'
```

This happens because the compiler tries multiple type conversions when ambiguous.

---

## 4. Import Issues

### The Problem

Circular imports (importing your own module from within) cause warnings in Swift 6.

### The Solution

Remove self-imports.

**Before:**
```swift
// In Multisig/UI/WalletConnect/.../MockJSONHttpClient.swift
import Multisig  // ❌ Importing own module
```

**After:**
```swift
// import Multisig removed - not needed
```

### Files Fixed

- **MockJSONHttpClient.swift** (line 7)

---

## Warnings (Non-Critical)

These warnings exist but don't block compilation:

### 1. Unnecessary try/catch Blocks (4 instances)
- **File:** WebConnectionController.swift
- **Issue:** `WalletConnectSign.Request` initializer is no longer throwing in Swift 6
- **Impact:** Cosmetic only

### 2. Sendable Concurrency Warning (1 instance)
- **File:** WebConnectionController.swift, line 1017
- **Issue:** `WebConnectionController` doesn't conform to `Sendable` protocol
- **Impact:** Potential concurrency safety issue

### 3. Core Data Inverse Relationships (3 warnings)
- **Issue:** Missing inverse relationships in Core Data model
- **Impact:** Core Data optimization warnings

### 4. Package Dependency Warnings (3 warnings)
- **Issue:** Missing dependencies in package dependency graph
- **Impact:** Build system warnings

---

## Cascading Errors Pattern

**Important:** Compiler errors often cascade. Fixing one error reveals the next.

**Example from our migration:**

```
Error 1: Cannot convert value of type 'RawSpan' to expected argument type 'Eth.AccessList'
Fix 1:  Add explicit type annotation

Error 2: Argument type 'RawSpan' expected to be an instance of a class
Fix 2:  Change to direct conversion without .bytes
```

This is expected behavior - the compiler stops at the first error per line, so each fix reveals deeper issues.

---

## Best Practices for Swift 6

### 1. Data to Bytes Conversion
```swift
// ✅ Preferred
let bytes: [UInt8] = [UInt8](data)

// ❌ Avoid
let bytes = data.bytes           // Returns RawSpan
let bytes = Array(data.bytes)    // Type issues
```

### 2. Type Annotations
When in doubt, add explicit type annotations:
```swift
// ✅ Better in Swift 6
let saltBytes: [UInt8] = [UInt8](salt)

// ⚠️ Can cause issues
let saltBytes = [UInt8](salt)  // Might be ambiguous in some contexts
```

### 3. Module Qualification
Qualify types when there are name conflicts:
```swift
// ✅ Explicit
Foundation.Data(hex: string)

// ❌ Ambiguous
Data(hex: string)  // Which Data?
```

### 4. Access Control
No whitespace in compound access control:
```swift
// ✅ Correct
private(set) var property: Type

// ❌ Error in Swift 6
private (set) var property: Type
```

---

## Files Changed

### Summary
- **Total Files Modified:** 13
- **Total Lines Changed:** 50+
- **Compilation Errors Fixed:** 30+

### Complete List

1. `Multisig/Features/Connect to Web/Logic/WebConnectionController.swift`
2. `Multisig/Features/Connect to Web/UI/Signature Request/SignatureRequestViewController.swift`
3. `Multisig/Features/Data Export/ImportExportDataController.swift`
4. `Multisig/Logic/Models/PrivateKey/web3swift/BIP32HDNode.swift`
5. `Multisig/UI/Transaction/TransactionDetailsViewController/TransactionDetailsViewController.swift`
6. `Multisig/UI/Transaction/ExecuteTransaction/TransactionExecutionController.swift`
7. `Multisig/UI/ClaimToken/ClaimingAmountViewController/ClaimTokensViewController.swift`
8. `Multisig/UI/Transaction/TransactionDetailsViewController/TransactionDetailCellBuilder.swift`
9. `Multisig/UI/UI Library/View Controllers/ContainerViewController.swift`
10. `Multisig/UI/UI Library/Views/TokenAmountField.swift`
11. `Multisig/Data/Services/Utils/NetworkStatusObserver.swift`
12. `Multisig/Cross-layer/Logger/LogService.swift`
13. `Multisig/UI/WalletConnect/Server/Safes/Incoming Transaction/MockJSONHttpClient.swift`

---

## Search Patterns Used

To find similar issues in the future:

### RawSpan Issues
```bash
# Find .bytes with operations that won't work on RawSpan
grep -r "\.bytes\.count\|\.bytes\.last\|\.bytes\[" --include="*.swift"

# Find .bytes assignments
grep -r "var .* = .*\.bytes$\|let .* = .*\.bytes$" --include="*.swift"

# Find Array(.bytes) patterns
grep -r "Array\(.*\.bytes\)" --include="*.swift"
```

### Spacing Issues
```bash
# Find private (set) with space
grep -r "private (set)" --include="*.swift"
```

### Type Ambiguity
```bash
# Find Data(hex:) that might be ambiguous
grep -r "Data(hex:" --include="*.swift"
```

---

## Recommendations

### Immediate Actions
1. ✅ **Done:** All compilation errors fixed
2. ⏭️ **Test thoroughly** - Run all unit and integration tests
3. ⏭️ **Test on device** - Ensure runtime behavior is correct

### Short-term (Optional)
1. Fix non-critical warnings (try/catch, Sendable)
2. Update Core Data model inverse relationships
3. Review package dependencies

### Long-term
1. **Update project Swift version:**
   ```
   Change SWIFT_VERSION from 5.0 to 6.0 in project.pbxproj
   ```
   
2. **Adopt Swift 6 features:**
   - Complete concurrency checking
   - Use `sending` and `@Sendable` properly
   - Leverage non-copyable types where appropriate

3. **Update dependencies:**
   - Check for Swift 6 compatible versions
   - Update Package.swift and Podfile as needed

4. **Enable strict concurrency checking:**
   ```
   SWIFT_STRICT_CONCURRENCY = complete
   ```

---

## Lessons Learned

### 1. Version Mismatch Detection
**Symptom:** Confusing errors about types that don't seem related
**Cause:** Compiler using Swift 6 but code written for Swift 5
**Solution:** Check `swift --version` vs project's `SWIFT_VERSION`

### 2. RawSpan is Fundamental
Swift 6's `RawSpan` change affects **any code that uses `Data.bytes`**. This is a breaking change that requires code updates.

### 3. Compiler Errors Cascade
Don't be discouraged by many errors. They often cascade - fixing one reveals the next. Work methodically through each error.

### 4. Type Inference is Stricter
Swift 6 requires more explicit type annotations, especially with:
- Variable shadowing
- Generic types
- Module name conflicts

### 5. Search First, Fix Proactively
Use grep/search to find all instances of a pattern and fix them proactively rather than waiting for compilation errors.

---

## References

- [Swift Evolution - Swift 6.0](https://github.com/apple/swift-evolution)
- [SE-0390: `@noncopyable` Types](https://github.com/apple/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md)
- [Swift 6 Migration Guide (Apple)](https://developer.apple.com/documentation/swift)

---

## Appendix: Common Error Messages

### "Value of type 'RawSpan' has no member 'count'"
**Cause:** Using `.bytes.count` on Data  
**Fix:** Convert to array: `[UInt8](data).count`

### "Cannot convert value of type 'RawSpan' to expected argument type 'Eth.AccessList'"
**Cause:** Type ambiguity with module name conflicts  
**Fix:** Use explicit module qualification: `Foundation.Data(...)`

### "Argument type 'RawSpan' expected to be an instance of a class or class-constrained type"
**Cause:** Trying to use `Array(RawSpan)` or `[UInt8](RawSpan)`  
**Fix:** Don't use `.bytes`, convert directly: `[UInt8](data)`

### "Extraneous whitespace between attribute name and '('"
**Cause:** `private (set)` with space  
**Fix:** Remove space: `private(set)`

---

**Migration completed successfully on October 28, 2025**

*For questions or issues, refer to this document or check Swift 6 migration resources.*

