//
//  SelectAssetViewController.swift
//  Multisig
//
//  Created by Vitaly Katz on 09.12.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class SelectAssetViewController: LoadableViewController, UITableViewDelegate, UITableViewDataSource {
    
    enum Mode {
        case balances([TokenBalance])
        case transferAssets([TransferSelectableAsset])
    }
    
    private var mode: Mode = .balances([])
    private var filteredBalances: [TokenBalance] = []
    private var filteredTransferAssets: [TransferSelectableAsset] = []
    
    override var isEmpty: Bool {
        switch mode {
        case .balances: return filteredBalances.isEmpty
        case .transferAssets: return filteredTransferAssets.isEmpty
        }
    }
    
    private let tableBackgroundColor: UIColor = .backgroundPrimary

    convenience init(balances: [TokenBalance], chainId: String?) {
        self.init(namedClass: Self.superclass())
        let sorted = Self.sortBalances(balances)
        self.mode = .balances(sorted)
        self.filteredBalances = sorted.filter {
            Self.isWhitelisted(chainId: chainId, address: $0.address)
        }
    }
    
    convenience init(transferAssets: [TransferSelectableAsset]) {
        self.init(namedClass: Self.superclass())
        let sorted = Self.sortTransferAssets(transferAssets)
        self.mode = .transferAssets(sorted)
        self.filteredTransferAssets = sorted.filter {
            Self.isWhitelisted(chainId: $0.chainId, address: $0.token.address)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = "¿Qué querés retirar?"
        navigationItem.backButtonTitle = NSLocalizedString("button_back", comment: "Back button title")
        
        // Use a custom cell so we can show chain on the left and amount on the right (2-line layout).
        tableView.register(SelectAssetRowCell.self, forCellReuseIdentifier: SelectAssetRowCell.reuseID)
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.backgroundColor = tableBackgroundColor
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.refreshControl = nil
        
        emptyView.tintColor = .icon
        emptyView.setImage(
            UIImage(named: "tab-icon-balances")?.withRenderingMode(.alwaysTemplate)
                ?? UIImage(named: "ico-no-assets")!
        )
        emptyView.setTitle(NSLocalizedString("pending_vault_activation_message", comment: "Add assets to get started"))
        emptyView.refreshControl = nil
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onSuccess()
        Tracker.trackEvent(.assetsTransferSelect)
    }
    
    @objc override func willEnterForeground() {
        onSuccess()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .balances:
            return filteredBalances.count
        case .transferAssets:
            return filteredTransferAssets.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(SelectAssetRowCell.self, for: indexPath)
        switch mode {
        case .balances:
            let item = filteredBalances[indexPath.row]
            cell.setSymbol(item.symbol)
            cell.setChain("") // single-vault mode has no chain label
            cell.setFiat(Self.dustAwareFiatString(for: item))
            cell.setAmount(Self.dustAwareAmountString(for: item))
            applyMoneyMarketBadgeIfNeeded(cell: cell, category: item.category)
            if let image = item.image {
                cell.setImage(image)
            } else {
                cell.setImage(with: item.imageURL, placeholder: UIImage(named: "ico-token-placeholder")!)
            }
        case .transferAssets:
            let asset = filteredTransferAssets[indexPath.row]
            let token = asset.token
            cell.setSymbol(token.symbol)
            cell.setChain(asset.chainName)
            cell.setFiat(Self.dustAwareFiatString(for: token))         // 2 decimals from formatter (+ dust handling)
            cell.setAmount(Self.dustAwareAmountString(for: token))     // up to 5 decimals, no symbol (+ dust handling)
            applyMoneyMarketBadgeIfNeeded(cell: cell, category: token.category)
            if let image = token.image {
                cell.setImage(image)
            } else {
                cell.setImage(with: token.imageURL, placeholder: UIImage(named: "ico-token-placeholder")!)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let transferFundsVC = TransferAmountViewController()
        let ribbon = RibbonViewController(rootViewController: transferFundsVC)
        switch mode {
        case .balances:
            transferFundsVC.tokenBalance = filteredBalances[indexPath.row]
        case .transferAssets:
            let asset = filteredTransferAssets[indexPath.row]
            asset.preferredSafe.select()
            transferFundsVC.tokenBalance = asset.preferredSafeToken
        }
        show(ribbon, sender: self)
    }
}

extension SelectAssetViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let inverseSet = CharacterSet(charactersIn:"0123456789").inverted

        let components = string.components(separatedBy: inverseSet)

        let filtered = components.joined(separator: "")

        if filtered == string {
            return true
        } else {
            if string == "." {
                let countdots = textField.text!.components(separatedBy:".").count - 1
                if countdots == 0 {
                    return true
                }else{
                    if countdots > 0 && string == "." {
                        return false
                    } else {
                        return true
                    }
                }
            }else{
                return false
            }
        }
    }
}

// MARK: - Dust formatting helpers
private extension SelectAssetViewController {
    static func isWhitelisted(chainId: String?, address: String) -> Bool {
        let trimmedChainId = (chainId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChainId.isEmpty else { return false }
        return TokenWhitelist.isWhitelisted(chainId: trimmedChainId, networkAddress: address)
    }

    /// If token has a positive balance but rounds to 0 with our "up to 5 decimals" display, show "<0.00001".
    static func dustAwareAmountString(for token: TokenBalance) -> String {
        let formatted = token.balanceFormatted5
        guard token.balanceValue.value > 0 else { return formatted }
        // If it already renders as non-zero, keep it.
        if formatted != "0" && formatted != "0.0" && formatted != "0,0" { return formatted }

        // Localize the decimal separator but keep the threshold fixed (5 fraction digits).
        let decimalSeparator = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        let threshold = "0\(decimalSeparator)00001"
        return "<\(threshold)"
    }

    /// Optional dust handling for fiat: if fiatValue is > 0 but would display as 0.00, show "<0.01 {code}".
    static func dustAwareFiatString(for token: TokenBalance) -> String {
        let formatted = token.fiatBalance
        guard token.fiatValue > 0 else { return formatted }

        // Extract number portion by removing trailing currency code if present.
        // `TokenBalance.displayCurrency` returns "{number} {code}".
        let parts = formatted.split(separator: " ")
        guard parts.count >= 2 else { return formatted }
        let numberPart = String(parts[0])
        let codePart = parts.dropFirst().joined(separator: " ")

        // If it already renders as non-zero, keep it.
        if numberPart != "0.00" && numberPart != "0,00" { return formatted }

        let decimalSeparator = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        let threshold = "0\(decimalSeparator)01"
        return "<\(threshold) \(codePart)"
    }
}

// MARK: - Sorting helpers
private extension SelectAssetViewController {
    static func sortBalances(_ balances: [TokenBalance]) -> [TokenBalance] {
        balances.sorted {
            if $0.fiatValue == $1.fiatValue {
                return $0.symbol.localizedCaseInsensitiveCompare($1.symbol) == .orderedAscending
            }
            return $0.fiatValue > $1.fiatValue
        }
    }
    
    static func sortTransferAssets(_ assets: [TransferSelectableAsset]) -> [TransferSelectableAsset] {
        assets.sorted {
            if $0.token.fiatValue == $1.token.fiatValue {
                if $0.token.symbol.caseInsensitiveCompare($1.token.symbol) == .orderedSame {
                    return $0.chainName.localizedCaseInsensitiveCompare($1.chainName) == .orderedAscending
                }
                return $0.token.symbol.localizedCaseInsensitiveCompare($1.token.symbol) == .orderedAscending
            }
            return $0.token.fiatValue > $1.token.fiatValue
        }
    }
}

// MARK: - Badge helpers
private extension SelectAssetViewController {
    func applyMoneyMarketBadgeIfNeeded(cell: SelectAssetRowCell, category: String) {
        let normalized = category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if normalized == "moneymarket" {
            cell.setBadge(text: "3.75%", backgroundColor: .success)
        } else {
            cell.setBadge(text: nil)
        }
    }
}
