# Session Summary – wrapLabel Balance Grouping (2025-12-30)

## Goal
- Add support for `TokenWhitelist.wrapLabel` so tokens sharing the same underlying asset (same `wrapLabel`) can be shown as a **single row** with **summed balance** and the **wrapLabel displayed as the symbol**.

## Key product decisions
- Grouping is **display-only** on the Assets/Balances list.
- Retirar/Send asset selection remains **ungrouped** (contract-level), to avoid ambiguity when multiple contracts share the same label.
- Decimals mismatch is **supported**: balances are summed precisely via integer scaling to the max decimals within a group.

## What shipped
### 1) Whitelist schema + sync
- Added `wrapLabel` to the CoreData `TokenWhitelist` entity and persisted it on sync.
- `TokenWhitelistService` already used `convertFromSnakeCase`, so decoding supports both `wrapLabel` and `wrap_label`.

### 2) Assets list grouping (single-vault + multivault)
- Single-vault Assets list:
  - Still posts `.balanceUpdated` with **raw balances**.
  - Renders table using a **display list** aggregated by wrapLabel.
- Multi-vault aggregated balances:
  - Updated `MultiVaultBalancesAggregator` to group by `wrapLabel ?? symbol` and sum balances with decimals scaling.
  - Transfer selection (`MultiVaultTransferAssetsAggregator`) intentionally remains contract-level and ungrouped.

### 3) Savings token detail breakdown
- Savings per-network breakdown now matches by the same display symbol (`wrapLabel ?? symbol`) and sums with decimals scaling so totals are consistent with the list.

### 4) Backfill behavior (fix for “no grouping during testing”)
- Added a one-time forced whitelist sync when a device has an old local whitelist with **zero** wrapLabels.
  - This addresses testers who synced the whitelist before `wrapLabel` existed.
  - Added DEBUG logging to show `wrapLabelNonEmpty` count on sync.

## Debugging note from testing
- In the screenshot, **RBTC showed under `BLACKTOKEN`**, which indicates whitelist lookup failed for that token, so `wrapLabel` couldn’t be resolved.
- The provided token list JSON shows a likely backend/data issue for RBTC: `"ChainID": "Ho"` (string) instead of chain 30, so it would never match app chainId `"30"`.
- Next debugging step is to confirm the runtime whitelist sync logs show `wrapLabelNonEmpty > 0`, and that whitelist entries have correct `chainId` + `networkAddress` for affected tokens.

## Touched files
- `Shared/CoreData/Multisig.xcdatamodeld/Multisig.xcdatamodel/contents`
- `Multisig/Data/Services/Backend/TokenWhitelistService.swift`
- `Multisig/Logic/Models/TokenWhitelist.swift`
- `Multisig/UI/Assets/BalancesViewController/WrapLabelBalancesAggregator.swift`
- `Multisig/UI/Assets/BalancesViewController/BalancesViewController.swift`
- `Multisig/UI/Assets/TokenBalanceBreakdownBuilder.swift`
- `Multisig/UI/Assets/TokenDetail/TokenBalanceBreakdownBuilder.swift`
- `Multisig/Data/Services/Backend/TokenWhitelistRepository.swift`
- `docs/whitelist-sync.md`
- `Multisig.xcodeproj/project.pbxproj`





