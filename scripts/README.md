# Tangem SDK Patch Scripts

## Build from MIT source (recommended for license compliance)

To ensure the embedded Tangem SDK uses **only** the MIT-licensed version (before the July 2025 license change), build the XCFramework from the local snapshot at commit `80419771`:

```bash
./scripts/build-tangem-sdk-from-mit.sh
```

By default the script uses `../tangem-sdk-ios-mit`. To use another path:

```bash
TANGEM_MIT_SOURCE=/path/to/tangem-sdk-ios-mit ./scripts/build-tangem-sdk-from-mit.sh
```

- **Provenance and license:** [../docs/TANGEM-SDK-PROVENANCE.md](../docs/TANGEM-SDK-PROVENANCE.md)

---

## Quick Reference

### 1. Analyze Binary (First Time)
```bash
./scripts/analyze-tangem-binary.sh
```
Shows key string locations to help with binary analysis in Hopper.

### 2. Apply Patch (After Configuring)
```bash
./scripts/patch-tangem-sdk.sh
```
**Prerequisites:**
- Must analyze binary with Hopper first
- Must update `PATCH_OFFSET` and `ORIGINAL_BYTES` in script

**What it does:**
- Creates timestamped backup
- Verifies patch location
- Applies NOP instruction
- Re-signs binary

### 3. Verify Patch
```bash
./scripts/verify-tangem-patch.sh
```
Confirms patch was applied correctly.

### 4. Restore Original
```bash
./scripts/restore-tangem-sdk.sh
```
Rolls back to unpatched SDK from backup.

---

## Workflow

```
┌─────────────────────────────────┐
│ 1. analyze-tangem-binary.sh     │
│    • Find string offsets         │
│    • Shows analysis steps        │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ 2. Use Hopper Disassembler      │
│    • Open TangemSdk binary       │
│    • Search for target string    │
│    • Find firmware check         │
│    • Note offset & bytes         │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ 3. Edit patch-tangem-sdk.sh     │
│    • Set PATCH_OFFSET            │
│    • Set ORIGINAL_BYTES          │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ 4. Run patch-tangem-sdk.sh      │
│    • Backup created              │
│    • Patch applied               │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ 5. verify-tangem-patch.sh       │
│    • Confirm patch worked        │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ 6. Clean & rebuild in Xcode     │
│    • Test signing                │
│    • Verify single scan          │
└─────────────────────────────────┘

     If issues: restore-tangem-sdk.sh
```

---

## Documentation

- **SDK provenance (MIT):** `../docs/TANGEM-SDK-PROVENANCE.md` – commit, license, how to rebuild
- **Quick Start:** `../docs/TANGEM-PATCH-QUICKSTART.md`
- **Technical Plan:** `../docs/tangem-sdk-binary-patch-plan.md`
- **Integration Summary:** `../docs/TANGEM-INTEGRATION-SUMMARY.md`

---

## Files

| Script | Purpose |
|--------|---------|
| `build-tangem-sdk-from-mit.sh` | Build XCFramework from MIT snapshot (commit 80419771); replace in project |
| `analyze-tangem-binary.sh` | Analysis helper - find string offsets |
| `patch-tangem-sdk.sh` | Apply binary patch to remove firmware check |
| `restore-tangem-sdk.sh` | Restore original SDK from backup |
| `verify-tangem-patch.sh` | Verify patch was applied correctly |

All scripts are safe - they create backups before making changes.

