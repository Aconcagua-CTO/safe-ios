//
//  SignAndReadTask.swift
//  Multisig
//
//  Mirrors the official Tangem app's SignAndReadTask implementation
//  Combines signing and reading in one NFC session for optimal performance
//

import Foundation
import TangemSdk

class SignAndReadTask: CardSessionRunnable {
    private let hashes: [Data]
    private let seedKey: Data
    private let pairWalletPublicKey: Data?
    private let hdKey: HDKey?

    private var signCommand: SignHashesCommand?

    init(hashes: [Data], seedKey: Data, pairWalletPublicKey: Data?, hdKey: HDKey?) {
        self.hashes = hashes
        self.seedKey = seedKey
        self.pairWalletPublicKey = pairWalletPublicKey
        self.hdKey = hdKey

        print("🔍 SignAndReadTask ▶️ INITIALIZED")
        print("   📝 Hashes to sign: \(hashes.count)")
        for (i, hash) in hashes.enumerated() {
            print("      Hash[\(i)]: \(hash.hexString)")
        }
        print("   🔑 Seed key: \(seedKey.hexString)")
        print("   👫 Pair wallet public key: \(pairWalletPublicKey?.hexString ?? "none")")
        if let hdKey {
            print("   🏠 HD key blockchain: \(hdKey.blockchainKey.hexString)")
            print("   🛤️ Derivation path: \(hdKey.derivationPath.rawPath)")
        }
    }

    func run(in session: CardSession, completion: @escaping CompletionResult<SignAndReadTaskResponse>) {
        print("▶️ SignAndReadTask ▶️ RUN called")
        print("   🌍 Session environment details:")
        print("      💳 Card ID: \(session.environment.card?.cardId ?? "none")")
        print("      🔐 Access code set: \(session.environment.card?.isAccessCodeSet ?? false)")
        print("      🔢 Firmware: \(session.environment.card?.firmwareVersion.stringValue ?? "unknown")")
        print("      🔗 Linked terminal enabled: \(session.environment.card?.settings.isLinkedTerminalEnabled ?? false)")
        print("      🔗 Linked terminal status: \(session.environment.card?.linkedTerminalStatus.rawValue ?? "unknown")")

        sign(in: session, key: seedKey, hdKey: hdKey) { signResult in
            switch signResult {
            case .success(let response):
                print("✅ SignAndReadTask ▶️ Sign completed successfully")
                print("   📝 Response signatures: \(response.signatures.count)")
                for (i, sig) in response.signatures.enumerated() {
                    print("      Sig[\(i)]: \(sig.hexString)")
                }
                print("   🔑 Response public key: \(response.publicKey.hexString)")
                print("   💳 Card ID: \(response.card.cardId)")
                print("   🔗 Linked terminal status: \(response.card.linkedTerminalStatus.rawValue)")
                completion(.success(response))
            case .failure(TangemSdkError.walletNotFound):
                print("⚠️ SignAndReadTask ▶️ Wallet not found, trying pair wallet")
                self.signWithPairWalletPublicKey(in: session, completion: completion)
            case .failure(let error):
                print("❌ SignAndReadTask ▶️ Sign failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    private func signWithPairWalletPublicKey(in session: CardSession, completion: @escaping CompletionResult<SignAndReadTaskResponse>) {
        print("🔄 SignAndReadTask ▶️ signWithPairWalletPublicKey called")

        guard let pairWalletPublicKey else {
            print("❌ SignAndReadTask ▶️ No pair wallet public key available")
            completion(.failure(TangemSdkError.walletNotFound))
            return
        }

        print("🔑 SignAndReadTask ▶️ Using pair wallet public key: \(pairWalletPublicKey.hexString)")

        // We don't have derivation for `Twin` cards
        sign(in: session, key: pairWalletPublicKey, hdKey: .none, completion: completion)
    }

    private func sign(in session: CardSession, key: Data, hdKey: HDKey?, completion: @escaping CompletionResult<SignAndReadTaskResponse>) {
        print("🔐 SignAndReadTask ▶️ sign() called")
        print("   🔑 Using key: \(key.hexString)")
        print("   🛤️ Derivation path: \(hdKey?.derivationPath.rawPath ?? "none")")
        print("   📝 Hashes to sign: \(hashes.count)")
        for (i, hash) in hashes.enumerated() {
            print("      Hash[\(i)]: \(hash.hexString)")
        }

        signCommand = SignHashesCommand(hashes: hashes, walletPublicKey: key, derivationPath: hdKey?.derivationPath)

        print("📤 SignAndReadTask ▶️ Created SignHashesCommand with:")
        print("   📝 Hashes: \(hashes.count)")
        print("   🔑 Wallet public key: \(key.hexString)")
        print("   🛤️ Derivation path: \(hdKey?.derivationPath.rawPath ?? "none")")
        print("   🎯 About to execute signing command...")

        signCommand!.run(in: session) { signResult in
            print("📥 SignAndReadTask ▶️ SignHashesCommand execution completed")

            switch signResult {
            case .success(let signResponse):
                print("✅ SignAndReadTask ▶️ SignHashesCommand SUCCESS")
                print("   📝 Signatures received: \(signResponse.signatures.count)")
                for (i, sig) in signResponse.signatures.enumerated() {
                    print("      Sig[\(i)]: \(sig.hexString) (length: \(sig.count) bytes)")
                }
                print("   🔢 Total signed hashes: \(signResponse.totalSignedHashes ?? -1)")
                print("   💳 Card ID: \(signResponse.cardId)")

                // Check if card state changed after signing
                if let updatedCard = session.environment.card {
                    print("   🔄 Card state after signing:")
                    print("      🔗 Linked terminal status: \(updatedCard.linkedTerminalStatus.rawValue)")
                    print("      🔢 Total signed hashes on card: \(updatedCard.wallets.first?.totalSignedHashes ?? -1)")
                    print("      🔢 Remaining signatures: \(updatedCard.wallets.first?.remainingSignatures ?? -1)")
                }

                let publicKey = hdKey?.blockchainKey ?? key
                print("🔑 SignAndReadTask ▶️ Using public key for response: \(publicKey.hexString)")

                let response = SignAndReadTaskResponse(
                    publicKey: publicKey,
                    signatures: signResponse.signatures,
                    card: session.environment.card!
                )

                print("📤 SignAndReadTask ▶️ Returning success response")
                completion(.success(response))

            case .failure(let error):
                print("❌ SignAndReadTask ▶️ SignHashesCommand FAILED: \(error)")
                print("   🔍 Error details: \(String(describing: error))")
                completion(.failure(error))
            }
        }
    }
}

extension SignAndReadTask {
    struct SignAndReadTaskResponse {
        let publicKey: Data
        let signatures: [Data]
        let card: Card
    }
}