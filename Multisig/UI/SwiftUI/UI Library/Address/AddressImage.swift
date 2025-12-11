//
//  AddressImage.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 17.07.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import SwiftUI

struct AddressImage: View {
    let address: Address?
    
    @ViewBuilder var body: some View {
        if address != nil {
            Image(address: address)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
        } else {
            Circle().foregroundColor(.backgroundSecondary)
        }
    }
}

extension AddressImage {
    init(_ value: String?) {
        self.init(address: value.map { Address(exactly: $0) })
    }
}

struct AddressImage_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AddressImage(address: "0x1230B3d59858296A31053C1b8562Ecf89A2f888b")
            AddressImage(address: nil)
        }
    }
}
