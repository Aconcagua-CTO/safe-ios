//
//  Image+Blockies.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 17.07.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import SwiftUI
import UIKit

extension Image {
    init(address: Address?,
         placeholderName: String = "ico-safe-bar-logo") {
        self.init(placeholderName)
    }
}

struct Image_Blockies_Previews: PreviewProvider {
    static let addresses: [Address] = [
        "0x0000000000000000000000000000000000000000",
        "0x2333b4CC1F89a0B4C43e9e733123C124aAE977EE",
        "0x1230B3d59858296A31053C1b8562Ecf89A2f888b",
    ]

    static var previews: some View {
        ForEach(addresses, id: \.self) { item in
            Image(address: item)
                .previewLayout(.sizeThatFits)
                .previewDisplayName(item.checksummed)
        }
    }
}
