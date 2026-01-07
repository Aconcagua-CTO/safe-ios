//
//  MultipleSignTask.swift
//  Multisig
//
//  Mirrors the official Tangem app's MultipleSignTask implementation
//  Uses SignAndReadTask internally for proper terminal linking
//

import Foundation
import TangemSdk

// HDKey struct shared between MultipleSignTask and SignAndReadTask
struct HDKey {
    let blockchainKey: Data
    let derivationPath: DerivationPath
}

struct SignData {
    let derivationPath: DerivationPath?
    let hashes: [Data]
    let publicKey: Data
}

class MultipleSignTask: CardSessionRunnable {
    private let dataToSign: [SignData]
    private let seedKey: Data
    private let pairWalletPublicKey: Data?

    init(dataToSign: [SignData], seedKey: Data, pairWalletPublicKey: Data? = nil) {
        self.dataToSign = dataToSign
        self.seedKey = seedKey
        self.pairWalletPublicKey = pairWalletPublicKey

        print("🔄 MultipleSignTask ▶️ INITIALIZED")
        print("   📊 Data to sign: \(dataToSign.count) items")
        print("   🔑 Seed key: \(seedKey.hexString)")
        print("   👫 Pair wallet public key: \(pairWalletPublicKey?.hexString ?? "none")")

        for (i, data) in dataToSign.enumerated() {
            print("   📝 SignData[\(i)]:")
            print("      Hashes: \(data.hashes.count)")
            for (j, hash) in data.hashes.enumerated() {
                print("         Hash[\(j)]: \(hash.hexString)")
            }
            print("      Public key: \(data.publicKey.hexString)")
            print("      Derivation path: \(data.derivationPath?.rawPath ?? "none")")
        }
    }

    func run(in session: CardSession, completion: @escaping CompletionResult<[MultipleSignTaskResponse]>) {
        print("▶️ MultipleSignTask ▶️ RUN called")
        print("   🌍 Session card: \(session.environment.card?.cardId ?? "none")")
        print("   🔗 Linked terminal enabled: \(session.environment.card?.settings.isLinkedTerminalEnabled ?? false)")

        runSign(at: 0, session: session, partialResult: [], completion: completion)
    }

    private func runSign(
        at index: Int,
        session: CardSession,
        partialResult: [MultipleSignTaskResponse],
        completion: @escaping CompletionResult<[MultipleSignTaskResponse]>
    ) {
        print("🔄 MultipleSignTask ▶️ runSign() at index \(index)/\(dataToSign.count)")

        guard index < dataToSign.count else {
            print("✅ MultipleSignTask ▶️ All sign operations completed")
            print("   📊 Partial results: \(partialResult.count)")
            if partialResult.count == dataToSign.count {
                print("   🎯 SUCCESS: All operations completed")
                completion(.success(partialResult))
            } else {
                print("   ❌ FAILURE: Missing results (\(partialResult.count) vs \(dataToSign.count))")
                completion(.failure(TangemSdkError.signHashesNotAvailable))
            }
            return
        }

        let signData = dataToSign[index]
        print("📤 MultipleSignTask ▶️ Processing SignData[\(index)]")
        print("   📝 Hashes: \(signData.hashes.count)")
        print("   🔑 Public key: \(signData.publicKey.hexString)")

        let hdKey = signData.derivationPath.map {
            HDKey(blockchainKey: signData.publicKey, derivationPath: $0)
        }

        let signCommand = SignAndReadTask(
            hashes: signData.hashes,
            seedKey: seedKey,
            pairWalletPublicKey: pairWalletPublicKey,
            hdKey: hdKey
        )

        print("🚀 MultipleSignTask ▶️ Created SignAndReadTask, executing...")

        signCommand.run(in: session) { result in
            print("📥 MultipleSignTask ▶️ SignAndReadTask completed for index \(index)")

            switch result {
            case .success(let signResponse):
                print("✅ MultipleSignTask ▶️ SignAndReadTask SUCCESS for index \(index)")
                print("   📝 Signatures: \(signResponse.signatures.count)")
                print("   🔑 Public key: \(signResponse.publicKey.hexString)")

                guard signResponse.signatures.count == signData.hashes.count else {
                    print("❌ MultipleSignTask ▶️ Signature count mismatch: got \(signResponse.signatures.count), expected \(signData.hashes.count)")
                    completion(.failure(TangemSdkError.signHashesNotAvailable))
                    return
                }

                var partialResult = partialResult
                let response = MultipleSignTaskResponse(
                    signatures: signResponse.signatures,
                    card: signResponse.card,
                    publicKey: signData.publicKey,
                    hashes: signData.hashes
                )

                partialResult.append(response)
                print("📊 MultipleSignTask ▶️ Added response, now have \(partialResult.count) results")

                self.runSign(at: index + 1, session: session, partialResult: partialResult, completion: completion)

            case .failure(let error):
                print("❌ MultipleSignTask ▶️ SignAndReadTask FAILED for index \(index): \(error)")
                completion(.failure(error))
            }
        }
    }
}

extension MultipleSignTask {
    struct MultipleSignTaskResponse {
        let signatures: [Data]
        let card: Card
        let publicKey: Data
        let hashes: [Data]
    }
}