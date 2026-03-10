//
//  Tangem0MultipleSignTask.swift
//  Multisig
//
//  Tangem0 variant of MultipleSignTask that uses Tangem0SignAndReadTask
//  (which uses SignRawHashesCommand) instead of SignAndReadTask.
//

import Foundation
import TangemSdk

class Tangem0MultipleSignTask: CardSessionRunnable {
    private let dataToSign: [SignData]
    private let seedKey: Data
    private let pairWalletPublicKey: Data?

    init(dataToSign: [SignData], seedKey: Data, pairWalletPublicKey: Data? = nil) {
        self.dataToSign = dataToSign
        self.seedKey = seedKey
        self.pairWalletPublicKey = pairWalletPublicKey

        print("🔄 Tangem0MultipleSignTask ▶️ INITIALIZED (SignRaw)")
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

    func run(in session: CardSession, completion: @escaping CompletionResult<[MultipleSignTask.MultipleSignTaskResponse]>) {
        print("▶️ Tangem0MultipleSignTask ▶️ RUN called (SignRaw)")
        print("   🌍 Session card: \(session.environment.card?.cardId ?? "none")")
        print("   🔗 Linked terminal enabled: \(session.environment.card?.settings.isLinkedTerminalEnabled ?? false)")

        runSign(at: 0, session: session, partialResult: [], completion: completion)
    }

    private func runSign(
        at index: Int,
        session: CardSession,
        partialResult: [MultipleSignTask.MultipleSignTaskResponse],
        completion: @escaping CompletionResult<[MultipleSignTask.MultipleSignTaskResponse]>
    ) {
        print("🔄 Tangem0MultipleSignTask ▶️ runSign() at index \(index)/\(dataToSign.count)")

        guard index < dataToSign.count else {
            print("✅ Tangem0MultipleSignTask ▶️ All sign operations completed")
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
        print("📤 Tangem0MultipleSignTask ▶️ Processing SignData[\(index)]")
        print("   📝 Hashes: \(signData.hashes.count)")
        print("   🔑 Public key: \(signData.publicKey.hexString)")

        let hdKey = signData.derivationPath.map {
            HDKey(blockchainKey: signData.publicKey, derivationPath: $0)
        }

        let signCommand = Tangem0SignAndReadTask(
            hashes: signData.hashes,
            seedKey: seedKey,
            pairWalletPublicKey: pairWalletPublicKey,
            hdKey: hdKey
        )

        print("🚀 Tangem0MultipleSignTask ▶️ Created Tangem0SignAndReadTask (SignRaw), executing...")

        signCommand.run(in: session) { result in
            print("📥 Tangem0MultipleSignTask ▶️ Tangem0SignAndReadTask completed for index \(index)")

            switch result {
            case .success(let signResponse):
                print("✅ Tangem0MultipleSignTask ▶️ Tangem0SignAndReadTask SUCCESS for index \(index)")
                print("   📝 Signatures: \(signResponse.signatures.count)")
                print("   🔑 Public key: \(signResponse.publicKey.hexString)")

                guard signResponse.signatures.count == signData.hashes.count else {
                    print("❌ Tangem0MultipleSignTask ▶️ Signature count mismatch: got \(signResponse.signatures.count), expected \(signData.hashes.count)")
                    completion(.failure(TangemSdkError.signHashesNotAvailable))
                    return
                }

                var partialResult = partialResult
                let response = MultipleSignTask.MultipleSignTaskResponse(
                    signatures: signResponse.signatures,
                    card: signResponse.card,
                    publicKey: signData.publicKey,
                    hashes: signData.hashes
                )

                partialResult.append(response)
                print("📊 Tangem0MultipleSignTask ▶️ Added response, now have \(partialResult.count) results")

                self.runSign(at: index + 1, session: session, partialResult: partialResult, completion: completion)

            case .failure(let error):
                print("❌ Tangem0MultipleSignTask ▶️ Tangem0SignAndReadTask FAILED for index \(index): \(error)")
                completion(.failure(error))
            }
        }
    }
}
