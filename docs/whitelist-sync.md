# Token Whitelist Sync (iOS)

- Data model: CoreData entity `TokenWhitelist` (id, tokenSymbol, tokenName, tokenType, tokenCategory, wrapLabel, network, networkAddress, decimals, chainId, enabled, stable, rebasing, native, erc20, image, descriptionText).
- Network: `TokenWhitelistService` calls backend `GET /tokensWhitelist` (market functions base URL).
- Repository: `TokenWhitelistRepository.syncWhitelist(force:, network:)` upserts into CoreData (guarded by auth, dedup by id).
- Triggers:
  - Post-login (LoginViewModel) runs whitelist sync (non-blocking).
  - Manual refresh in SwitchSafesViewController triggers whitelist sync alongside vault refresh.
- Accessors: `TokenWhitelist.all`, `TokenWhitelist.by(id:)`, `TokenWhitelist.by(network:)` for consumers.

