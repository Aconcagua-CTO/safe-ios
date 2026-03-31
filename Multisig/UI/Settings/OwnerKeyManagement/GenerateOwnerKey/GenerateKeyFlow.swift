//
//  GenerateKeyFlow.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 04.05.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit

/// Flow for generating a new private key
///
/// Screen sequence:
///
/// 1. Intro (in superclass)
/// 2. Key is generated
/// 3. Enter Name (in superclass)
/// 4. Create Passcode (in superclass)
/// 5. Backup Key
/// 6. Add Key as Safe Owner
/// 6.1. Add as new owner OR
/// 6.2. Replace existing owner
/// 7. If user selected 'open tx details' then flow closes.
/// 7.1. Otherwise, Key Details screen
class GenerateKeyFlow: AddKeyFlow {
    var flowFactory: GenerateKeyFactory {
        factory as! GenerateKeyFactory
    }

    var safe: Safe?

    var backupFlow: BackupFlow!
    var addOwnerFlow: AddOwnerFlow!
    var replaceOwnerFlow: ReplaceOwnerFlow!

    var parameters: GenerateKeyParameters? {
        keyParameters as? GenerateKeyParameters
    }

    init(completion: @escaping (Bool) -> Void) {
        super.init(factory: GenerateKeyFactory(), completion: completion)
    }

    override func didIntro() {
        let privateKey = OwnerKeyController.generate()
        // Streamlined flow: don't prompt for a name; always use "Mobile Key".
        keyParameters = GenerateKeyParameters(address: privateKey.address, keyName: "Mobile Key", privateKey: privateKey)
        didGetKey()
    }

    override func didGetKey() {
        // Streamlined flow: skip the name entry screen.
        // `didIntro()` already sets the name, but we ensure it's present here as well.
        if keyParameters?.name == nil {
            keyParameters?.name = "Mobile Key"
        }
        importKey()
    }

    override func doImport() -> Bool {
        guard let privateKey = parameters?.privateKey,
              let name = parameters?.name else {
            assertionFailure("Missing key arguments")
            return false
        }

        return OwnerKeyController.importKey(privateKey, name: name, type: .deviceGenerated, isDerivedFromSeedPhrase: true)
    }

    func backup() {
        guard let mnemonic = parameters?.privateKey?.mnemonic else {
            assertionFailure("No mnemonic found")
            return
        }

        backupFlow = BackupFlow(mnemonic: mnemonic) { [unowned self] _ in
            backupFlow = nil
            addKeyAsOwner()
        }
        push(flow: backupFlow)
    }

    func addKeyAsOwner() {
        safe = try? Safe.getSelected()
        didAddKeyAsOwner(openKeyDetails: false)
    }

    func addOwner() {
        guard let address = parameters?.address else {
            assertionFailure("Missing key arguments")
            return
        }
        addOwnerFlow = AddOwnerFlow(newOwner: address, safe: safe!) { [unowned self] skippedTxDetails in
            addOwnerFlow = nil
            didAddKeyAsOwner(openKeyDetails: skippedTxDetails)
        }
        push(flow: addOwnerFlow)
    }

    func replaceOwner() {
        replaceOwnerFlow = ReplaceOwnerFlow(newOwner: parameters!.address, safe: safe!) { [unowned self] skippedTxDetails in
            replaceOwnerFlow = nil
            didReplaceKeyAsOwner(openKeyDetails: skippedTxDetails)
        }
        push(flow: replaceOwnerFlow)
    }

    func didAddKeyAsOwner(openKeyDetails: Bool = true) {
        guard openKeyDetails else {
            stop(success: true)
            return
        }
        details()
    }

    func didReplaceKeyAsOwner(openKeyDetails: Bool = true) {
        guard openKeyDetails else {
            stop(success: true)
            return
        }
        details()
    }

    func details() {
        guard let address = parameters?.address else {
            assertionFailure("Missing key arguments")
            return
        }

        navigationController.setNavigationBarHidden(false, animated: true)
        let key = try? KeyInfo.firstKey(address: address)
        assert(key != nil)
        let keyVC = flowFactory.details(keyInfo: key!) { [unowned self] in
            stop(success: true)
        }
        show(keyVC)
    }

    override func didDelegateKeySetup() {
        backup()
    }
}

class GenerateKeyFactory: AddKeyFlowFactory {
    override func intro(completion: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = super.intro(completion: completion)
        let passkeyHeroImage = UIImage(named: "ico-mobile-key-passkey")?.withRenderingMode(.alwaysOriginal)
        let lockImage = UIImage(named: "ico-lock")
        introVC.cards = [
            .init(image: passkeyHeroImage,
                  topIconLayout: .widePasskey,
                  title: NSLocalizedString("ui_mobile_key_create_intro_title", comment: "Intro title for mobile key creation"),
                  body: NSLocalizedString("ui_mobile_key_create_intro_body", comment: "Intro body for mobile key creation")),

            .init(image: lockImage,
                  title: NSLocalizedString("ui_mobile_key_create_secure_title", comment: "Security title for mobile key creation"),
                  body: NSLocalizedString("ui_mobile_key_create_secure_body", comment: "Security body for mobile key creation")),
        ]
        introVC.viewTrackingEvent = .generateOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_owner_key_create_title", comment: "Title for the generate owner key flow")
        introVC.navigationItem.largeTitleDisplayMode = .never
        return introVC
    }

    func inviteToAddOwner(share: @escaping () -> Void, onSkip: @escaping () -> ()) -> CreateInviteOwnerIntroViewController {
        let introVC = CreateInviteOwnerIntroViewController(onShare: share, onSkip: onSkip)
        ViewControllerFactory.makeTransparentNavigationBar(introVC)
        return introVC
    }

    func shareAddKeyAsOwnerLink(owner: Address, safe: Safe, onFinish: @escaping () -> Void) -> UIViewController {
        let vc = ShareAddOwnerLinkViewController(owner: owner,
                                                 safe: safe,
                                                 onFinish: onFinish)

        ViewControllerFactory.makeTransparentNavigationBar(vc)
        ViewControllerFactory.addCloseButton(vc)

        return vc
    }

    func addAsOwner(added: @escaping () -> Void, replaced: @escaping () -> Void, skipped: @escaping () -> Void) -> AddKeyAsOwnerIntroViewController {
        let introVC = AddKeyAsOwnerIntroViewController()
        ViewControllerFactory.makeTransparentNavigationBar(introVC)
        introVC.onAdd = added
        introVC.onReplace = replaced
        introVC.onSkip = skipped
        return introVC
    }
}

class GenerateKeyParameters: AddKeyParameters {
    var privateKey: PrivateKey?

    init(address: Address, keyName: String?, privateKey: PrivateKey?) {
        self.privateKey = privateKey
        super.init(address: address, name: keyName, type: KeyType.deviceGenerated)
    }
}
