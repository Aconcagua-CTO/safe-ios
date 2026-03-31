//
//  AddressBookEntriesRepository.swift
//  Multisig
//

import Foundation

protocol AddressBookEntriesRepository {
    func syncAddressBook(force: Bool, completion: @escaping (Result<Void, Error>) -> Void)
    func registerLocallyAddedEntry(address: String, name: String)
}

final class AddressBookEntriesRepositoryImpl: AddressBookEntriesRepository {
    private let service: AddressBookEntriesService
    private let authRepository: AuthRepository

    private var isSyncing = false
    private let syncQueue = DispatchQueue(label: "io.gnosis.multisig.addressBookEntriesSync", qos: .userInitiated)

    init(service: AddressBookEntriesService, authRepository: AuthRepository) {
        self.service = service
        self.authRepository = authRepository
    }

    func syncAddressBook(force: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            if self.isSyncing {
                completion(.success(()))
                return
            }
            self.isSyncing = true

            guard self.authRepository.isAuthenticated(),
                  let userId = self.authRepository.getCurrentUser()?.uid else {
                self.isSyncing = false
                completion(.failure(NSError(domain: "AddressBookEntriesRepository", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Not authenticated"
                ])))
                return
            }

            LogService.shared.info("[AddressBookEntries] Sync START force=\(force)")
            self.service.getAddressBookEntries(userId: userId) { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isSyncing = false
                    switch result {
                    case .success(let response):
                        for item in response.items {
                            guard let address = item.address,
                                  let name = item.name,
                                  let chainId = item.chainId,
                                  !address.isEmpty, !name.isEmpty,
                                  let chain = Chain.by(chainId) else { continue }
                            AddressBookEntry.addOrUpdate(address, chain: chain, name: name)
                        }
                        AddressBookEntry.updateCachedNames()
                        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
                        LogService.shared.info("[AddressBookEntries] Sync SUCCESS entries=\(response.items.count)")
                        completion(.success(()))
                    case .failure(let error):
                        LogService.shared.error("[AddressBookEntries] Sync FAILED: \(error.localizedDescription)", error: error)
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    func registerLocallyAddedEntry(address: String, name: String) {
        guard authRepository.isAuthenticated(),
              let userId = authRepository.getCurrentUser()?.uid else {
            LogService.shared.debug("[AddressBookEntries] registerLocallyAddedEntry skipped – not authenticated")
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let chainIds = AddressBookEntry.supportedChainIDs
            for chainId in chainIds {
                self.service.postEntry(userId: userId, address: address, name: name, chainId: chainId, source: "user") { result in
                    if case .failure(let error) = result {
                        LogService.shared.error("[AddressBookEntries] registerLocallyAddedEntry POST failed chainId=\(chainId)", error: error)
                    }
                }
            }
        }
    }
}
