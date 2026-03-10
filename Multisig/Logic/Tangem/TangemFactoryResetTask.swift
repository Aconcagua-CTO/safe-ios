//
//  TangemFactoryResetTask.swift
//  Multisig
//
//  Factory reset task for Tangem cards - deletes all wallets and resets backup system
//  ⚠️ WARNING: This operation is IRREVERSIBLE and will cause PERMANENT DATA LOSS!
//

import Foundation
import TangemSdk

/// Task to perform factory reset on a Tangem card
/// Deletes all wallets and resets backup system (if supported)
final class TangemFactoryResetTask: CardSessionRunnable {
    
    func run(in session: CardSession, completion: @escaping CompletionResult<Card>) {
        TangemLogger.info("🔥 FACTORY RESET TASK: Starting factory reset task")
        TangemLogger.debug("🔥 FACTORY RESET TASK: ═══ TASK INITIALIZATION ═══")
        
        guard let card = session.environment.card else {
            TangemLogger.error("🔥 FACTORY RESET TASK ERROR: No card found in session")
            completion(.failure(.cardError))
            return
        }
        
        TangemLogger.debug("🔥 FACTORY RESET TASK: Card found - Card ID: \(card.cardId)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Firmware: \(card.firmwareVersion.stringValue)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Wallets to delete: \(card.wallets.count)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Backup status: \(card.backupStatus != nil ? "present" : "nil")")
        
        // Analyze card type
        let isLegacyCard = card.cardId.hasPrefix("CB79")
        // Check if backup is supported by checking if backupStatus exists and is not nil
        let hasBackupSupport = card.backupStatus != nil
        
        TangemLogger.debug("🔥 FACTORY RESET TASK: ═══ CARD COMPATIBILITY ANALYSIS ═══")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Card ID: \(card.cardId)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Is Legacy CB79: \(isLegacyCard)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Has Backup Support: \(hasBackupSupport)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Reset Strategy: \(hasBackupSupport ? "Full Reset" : "Legacy Reset")")
        TangemLogger.debug("🔥 FACTORY RESET TASK: ═══ END COMPATIBILITY ANALYSIS ═══")
        
        // Validate preconditions
        if let error = validateResetPreconditions(card: card) {
            TangemLogger.error("🔥 FACTORY RESET TASK ERROR: Precondition validation failed")
            completion(.failure(error))
            return
        }
        
        TangemLogger.info("🔥 FACTORY RESET TASK: ✅ Preconditions validated, starting wallet deletion")
        
        // Step 1: Delete all wallets
        deleteAllWallets(in: session) { result in
            switch result {
            case .success:
                TangemLogger.info("🔥 FACTORY RESET TASK: ✅ All wallets deleted successfully")
                
                // Step 2: Reset backup system if supported
                if hasBackupSupport {
                    TangemLogger.debug("🔥 FACTORY RESET TASK: Applying modern card reset strategy")
                    self.resetBackupSystem(in: session, completion: completion)
                } else {
                    TangemLogger.debug("🔥 FACTORY RESET TASK: Legacy card - wallet deletion sufficient")
                    TangemLogger.info("🔥 FACTORY RESET TASK: ✅ Factory reset completed successfully")
                    completion(.success(card))
                }
                
            case .failure(let error):
                TangemLogger.error("🔥 FACTORY RESET TASK ERROR: Failed to delete wallets", error: error)
                completion(.failure(error))
            }
        }
    }
    
    private func validateResetPreconditions(card: Card) -> TangemSdkError? {
        TangemLogger.debug("🔥 FACTORY RESET TASK: Validating reset preconditions")
        
        // Check firmware version
        if card.firmwareVersion.major < 3 || (card.firmwareVersion.major == 3 && card.firmwareVersion.minor < 29) {
            TangemLogger.error("🔥 FACTORY RESET TASK ERROR: Firmware too old for reset operations")
            TangemLogger.debug("🔥 FACTORY RESET TASK: - Current firmware: \(card.firmwareVersion.stringValue)")
            TangemLogger.debug("🔥 FACTORY RESET TASK: - Minimum required: 3.29")
            return .notSupportedFirmwareVersion
        }
        
        // Check for permanent wallets
        let permanentWallets = card.wallets.filter { $0.settings.isPermanent }
        if !permanentWallets.isEmpty {
            TangemLogger.error("🔥 FACTORY RESET TASK ERROR: Found \(permanentWallets.count) permanent wallet(s)")
            permanentWallets.forEach { wallet in
                TangemLogger.debug("🔥 FACTORY RESET TASK: - Permanent wallet index: \(wallet.index)")
            }
            return .purgeWalletProhibited
        }
        
        TangemLogger.debug("🔥 FACTORY RESET TASK: ✅ Preconditions validated successfully")
        return nil
    }
    
    private func deleteAllWallets(in session: CardSession, completion: @escaping CompletionResult<Void>) {
        guard let card = session.environment.card else {
            TangemLogger.error("🔥 FACTORY RESET TASK ERROR: No card in session during wallet deletion")
            completion(.failure(.cardError))
            return
        }
        
        let wallets = card.wallets
        TangemLogger.info("🔥 FACTORY RESET TASK: Starting wallet deletion process")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Total wallets to delete: \(wallets.count)")
        
        if wallets.isEmpty {
            TangemLogger.info("🔥 FACTORY RESET TASK: No wallets to delete")
            completion(.success(()))
            return
        }
        
        // Delete wallets recursively
        deleteWalletRecursive(in: session, wallets: wallets, index: 0, completion: completion)
    }
    
    private func deleteWalletRecursive(in session: CardSession,
                                      wallets: [Card.Wallet],
                                      index: Int,
                                      completion: @escaping CompletionResult<Void>) {
        if index >= wallets.count {
            TangemLogger.info("🔥 FACTORY RESET TASK: ✅ All wallets deleted successfully")
            completion(.success(()))
            return
        }
        
        let wallet = wallets[index]
        let walletNumber = index + 1
        let totalWallets = wallets.count
        
        TangemLogger.info("🔥 FACTORY RESET TASK: Deleting wallet \(walletNumber)/\(totalWallets)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Wallet index: \(wallet.index)")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Public key: \(wallet.publicKey.map { String(format: "%02x", $0) }.joined().prefix(32))...")
        debugTrace(
            "PurgeWallet request",
            request: [
                "walletNumber=\(walletNumber)/\(totalWallets)",
                "walletIndex=\(wallet.index)",
                "publicKey=\(wallet.publicKey.map { String(format: "%02x", $0) }.joined())",
                "session.cardId=\(session.environment.card?.cardId ?? "nil")",
            ],
            expected: [
                "PurgeWalletCommand returns success",
                "wallet removed from card secure storage",
                "if default PINs are active, security delay may be enforced by card firmware",
            ]
        )
        
        let command = PurgeWalletCommand(publicKey: wallet.publicKey)
        command.run(in: session) { result in
            switch result {
            case .success:
                TangemLogger.info("🔥 FACTORY RESET TASK: ✅ Wallet \(walletNumber) deleted successfully")
                self.debugTrace(
                    "PurgeWallet response",
                    got: [
                        "result=success",
                        "walletNumber=\(walletNumber)/\(totalWallets)",
                    ]
                )
                // Continue with next wallet
                self.deleteWalletRecursive(in: session, wallets: wallets, index: index + 1, completion: completion)
                
            case .failure(let error):
                TangemLogger.error("🔥 FACTORY RESET TASK ERROR: Failed to delete wallet \(walletNumber)", error: error)
                TangemLogger.debug("🔥 FACTORY RESET TASK: - Error type: \(type(of: error))")
                TangemLogger.debug("🔥 FACTORY RESET TASK: - Error code: \(error.code)")
                self.debugTrace(
                    "PurgeWallet response",
                    got: [
                        "result=failure",
                        "walletNumber=\(walletNumber)/\(totalWallets)",
                        "errorType=\(type(of: error))",
                        "errorCode=\(error.code)",
                        "error=\(error)",
                    ]
                )
                completion(.failure(error))
            }
        }
    }
    
    private func resetBackupSystem(in session: CardSession, completion: @escaping CompletionResult<Card>) {
        guard let card = session.environment.card else {
            TangemLogger.error("🔥 FACTORY RESET TASK ERROR: No card in session during backup reset")
            completion(.failure(.cardError))
            return
        }
        
        let backupStatus = card.backupStatus
        TangemLogger.info("🔥 FACTORY RESET TASK: Starting backup system reset")
        TangemLogger.debug("🔥 FACTORY RESET TASK: - Current backup status: \(backupStatus != nil ? "present" : "nil")")
        
        if backupStatus == nil || backupStatus == .noBackup {
            TangemLogger.info("🔥 FACTORY RESET TASK: No backup system to reset")
            TangemLogger.info("🔥 FACTORY RESET TASK: ✅ Factory reset completed successfully")
            debugTrace(
                "ResetBackup skipped",
                got: [
                    "backupStatus=\(String(describing: backupStatus))",
                    "reason=no backup system on card",
                ]
            )
            completion(.success(card))
            return
        }
        
        TangemLogger.debug("🔥 FACTORY RESET TASK: Resetting backup system...")
        debugTrace(
            "ResetBackup request",
            request: [
                "command=ResetBackupCommand",
                "cardId=\(card.cardId)",
                "backupStatus=\(String(describing: backupStatus))",
            ],
            expected: [
                "ResetBackupCommand returns success",
                "card backup metadata cleared",
            ]
        )
        let command = ResetBackupCommand()
        command.run(in: session) { result in
            switch result {
            case .success:
                TangemLogger.info("🔥 FACTORY RESET TASK: ✅ Backup system reset successfully")
                TangemLogger.info("🔥 FACTORY RESET TASK: ✅ COMPLETE FACTORY RESET SUCCESSFUL")
                self.debugTrace(
                    "ResetBackup response",
                    got: [
                        "result=success",
                        "cardId=\(card.cardId)",
                    ]
                )
                completion(.success(card))
                
            case .failure(let error):
                TangemLogger.error("🔥 FACTORY RESET TASK ERROR: Failed to reset backup system", error: error)
                TangemLogger.debug("🔥 FACTORY RESET TASK: - Error type: \(type(of: error))")
                TangemLogger.debug("🔥 FACTORY RESET TASK: - Error code: \(error.code)")
                self.debugTrace(
                    "ResetBackup response",
                    got: [
                        "result=failure",
                        "cardId=\(card.cardId)",
                        "errorType=\(type(of: error))",
                        "errorCode=\(error.code)",
                        "error=\(error)",
                    ]
                )
                completion(.failure(error))
            }
        }
    }

    private func debugTrace(_ title: String, request: [String] = [], expected: [String] = [], got: [String] = []) {
#if DEBUG
        TangemLogger.debug("🧪 FACTORY RESET TRACE: \(title)")
        if !request.isEmpty {
            TangemLogger.debug("🧪 FACTORY RESET TRACE:   REQUEST:")
            request.forEach { TangemLogger.debug("🧪 FACTORY RESET TRACE:   - \($0)") }
        }
        if !expected.isEmpty {
            TangemLogger.debug("🧪 FACTORY RESET TRACE:   EXPECT:")
            expected.forEach { TangemLogger.debug("🧪 FACTORY RESET TRACE:   - \($0)") }
        }
        if !got.isEmpty {
            TangemLogger.debug("🧪 FACTORY RESET TRACE:   GOT:")
            got.forEach { TangemLogger.debug("🧪 FACTORY RESET TRACE:   - \($0)") }
        }
#endif
    }
}

