//
//  Tangem0SignAndReadTask.swift
//  Multisig
//
//  Tangem0 variant of SignAndReadTask that uses SignRawHashesCommand
//  to bypass SHA256 preprocessing and the firmware security delay.
//

import Foundation
import TangemSdk

class Tangem0SignAndReadTask: CardSessionRunnable {
    private let hashes: [Data]
    private let seedKey: Data
    private let pairWalletPublicKey: Data?
    private let hdKey: HDKey?

    private var signCommand: SignRawHashesCommand?

    init(hashes: [Data], seedKey: Data, pairWalletPublicKey: Data?, hdKey: HDKey?) {
        self.hashes = hashes
        self.seedKey = seedKey
        self.pairWalletPublicKey = pairWalletPublicKey
        self.hdKey = hdKey

        print("🔍 Tangem0SignAndReadTask ▶️ INITIALIZED (SignRaw)")
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

    func run(in session: CardSession, completion: @escaping CompletionResult<SignAndReadTask.SignAndReadTaskResponse>) {
        print("▶️ Tangem0SignAndReadTask ▶️ RUN called (SignRaw)")
        print("   🌍 Session environment details:")
        print("      💳 Card ID: \(session.environment.card?.cardId ?? "none")")
        print("      🔐 Access code set: \(session.environment.card?.isAccessCodeSet ?? false)")
        print("      🔢 Firmware: \(session.environment.card?.firmwareVersion.stringValue ?? "unknown")")
        print("      🔗 Linked terminal enabled: \(session.environment.card?.settings.isLinkedTerminalEnabled ?? false)")
        print("      🔗 Linked terminal status: \(session.environment.card?.linkedTerminalStatus.rawValue ?? "unknown")")

        sign(in: session, key: seedKey, hdKey: hdKey) { signResult in
            switch signResult {
            case .success(let response):
                print("✅ Tangem0SignAndReadTask ▶️ SignRaw completed successfully")
                print("   📝 Response signatures: \(response.signatures.count)")
                for (i, sig) in response.signatures.enumerated() {
                    print("      Sig[\(i)]: \(sig.hexString)")
                }
                print("   🔑 Response public key: \(response.publicKey.hexString)")
                print("   💳 Card ID: \(response.card.cardId)")
                print("   🔗 Linked terminal status: \(response.card.linkedTerminalStatus.rawValue)")
                completion(.success(response))
            case .failure(TangemSdkError.walletNotFound):
                print("⚠️ Tangem0SignAndReadTask ▶️ Wallet not found, trying pair wallet")
                self.signWithPairWalletPublicKey(in: session, completion: completion)
            case .failure(let error):
                print("❌ Tangem0SignAndReadTask ▶️ SignRaw failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    private func signWithPairWalletPublicKey(in session: CardSession, completion: @escaping CompletionResult<SignAndReadTask.SignAndReadTaskResponse>) {
        print("🔄 Tangem0SignAndReadTask ▶️ signWithPairWalletPublicKey called")

        guard let pairWalletPublicKey else {
            print("❌ Tangem0SignAndReadTask ▶️ No pair wallet public key available")
            completion(.failure(TangemSdkError.walletNotFound))
            return
        }

        print("🔑 Tangem0SignAndReadTask ▶️ Using pair wallet public key: \(pairWalletPublicKey.hexString)")

        sign(in: session, key: pairWalletPublicKey, hdKey: .none, completion: completion)
    }

    private func sign(in session: CardSession, key: Data, hdKey: HDKey?, completion: @escaping CompletionResult<SignAndReadTask.SignAndReadTaskResponse>) {
        print("🔐 Tangem0SignAndReadTask ▶️ sign() called (SignRaw)")
        print("   🔑 Using key: \(key.hexString)")
        print("   🛤️ Derivation path: \(hdKey?.derivationPath.rawPath ?? "none")")
        print("   📝 Hashes to sign: \(hashes.count)")
        for (i, hash) in hashes.enumerated() {
            print("      Hash[\(i)]: \(hash.hexString)")
        }

        signCommand = SignRawHashesCommand(hashes: hashes, walletPublicKey: key, derivationPath: hdKey?.derivationPath)

        print("📤 Tangem0SignAndReadTask ▶️ Created SignRawHashesCommand with:")
        print("   📝 Hashes: \(hashes.count)")
        print("   🔑 Wallet public key: \(key.hexString)")
        print("   🛤️ Derivation path: \(hdKey?.derivationPath.rawPath ?? "none")")
        print("   🎯 About to execute SignRaw signing command...")

        signCommand!.run(in: session) { signResult in
            print("📥 Tangem0SignAndReadTask ▶️ SignRawHashesCommand execution completed")

            switch signResult {
            case .success(let signResponse):
                print("✅ Tangem0SignAndReadTask ▶️ SignRawHashesCommand SUCCESS")
                print("   📝 Signatures received: \(signResponse.signatures.count)")
                for (i, sig) in signResponse.signatures.enumerated() {
                    print("      Sig[\(i)]: \(sig.hexString) (length: \(sig.count) bytes)")
                }
                print("   🔢 Total signed hashes: \(signResponse.totalSignedHashes ?? -1)")
                print("   💳 Card ID: \(signResponse.cardId)")

                if let updatedCard = session.environment.card {
                    print("   🔄 Card state after signing:")
                    print("      🔗 Linked terminal status: \(updatedCard.linkedTerminalStatus.rawValue)")
                    print("      🔢 Total signed hashes on card: \(updatedCard.wallets.first?.totalSignedHashes ?? -1)")
                    print("      🔢 Remaining signatures: \(updatedCard.wallets.first?.remainingSignatures ?? -1)")
                }

                let publicKey = hdKey?.blockchainKey ?? key
                print("🔑 Tangem0SignAndReadTask ▶️ Using public key for response: \(publicKey.hexString)")

                let response = SignAndReadTask.SignAndReadTaskResponse(
                    publicKey: publicKey,
                    signatures: signResponse.signatures,
                    card: session.environment.card!
                )

                print("📤 Tangem0SignAndReadTask ▶️ Returning success response")
                completion(.success(response))

            case .failure(let error):
                print("❌ Tangem0SignAndReadTask ▶️ SignRawHashesCommand FAILED: \(error)")
                print("   🔍 Error details: \(String(describing: error))")
                completion(.failure(error))
            }
        }
    }
}
