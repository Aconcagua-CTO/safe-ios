//
//  SafeInfoView.swift
//  Multisig
//
//  Created by Moaaz on 4/23/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import SwiftUI
import UIKit

// Info view split into two objects so that the content view would track
// changes to the safe, but the parent view tracks changes to the selection.
struct SafeInfoView: View {
    @FetchRequest(fetchRequest: Safe.fetchRequest().selected())
    var selectedSafe: FetchedResults<Safe>

    var body: some View {
        ZStack {
            if selectedSafe.first == nil {
                Text("No Safe is selected").body()
            } else {
                SafeInfoContentView(safe: selectedSafe.first!)
            }
        }
        .background(Color.backgroundSecondary)
    }
}

struct SafeInfoContentView: View {
    @ObservedObject var safe: Safe
    var body: some View {
        VStack (alignment: .center, spacing: 0) {
            AddressImage(safe.address)
                .frame(width: 56, height: 56)
                .padding(.top, 16)

            Text(NSLocalizedString("ui_receive_transfer_instructions", comment: "Deposit transfer instructions"))
                .font(.subheadline)
                .foregroundColor(.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)

            if safe.hasAddress {
                let prefix = prependingPrefixString()
                let address = safe.address ?? ""
                let copyValue = copyPrefixString() + address
                
                HStack(spacing: 0) {
                    Button(action: {
                        UIPasteboard.general.string = copyValue
                        App.shared.snackbar.show(message: "Copied to clipboard", duration: 2)
                        print("[SafeInfoView][ADDRESS TAP] Address copied to clipboard: \(copyValue)")
                    }) {
                        SlicedText(string: SlicedString(text: prefix + address, prefix: prefix.count + 6, suffix: 4))
                            .style(.addressLong)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    CopyButton(copyValue) {
                        Image(systemName: "doc.on.doc")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.primary)
                            .accessibilityLabel("Copy address")
                    }
                    .frameForTapping()
                }
                // keep the address visually centered, while attaching the trailing icon button
                .padding([.leading, .trailing], 44)
                .padding(.trailing, -44)
                .padding(.top, 6)
            }

            Text("Redes disponibles")
                .font(.subheadline)
                .foregroundColor(.labelSecondary)
                .padding(.top, 14)
            
            // Chain list (excluding the active network)
            chainListView
                .padding(.top, 8)
                .padding(.horizontal, 8)
            
            // WhatsApp link
            WhatsAppLinkView()
                .padding(.top, 16)
        }
        .multilineTextAlignment(.center)
        .onAppear {
            Tracker.trackEvent(.safeReceive)
        }
    }

    private func copyPrefixString() -> String {
        ""
    }

    private func prependingPrefixString() -> String {
        ""
    }
    
    private var chainListView: some View {
        let allChains: [(String, String?)] = [
            ("Ethereum", "1"),
            ("Rootstock", "30")
        ]
        
        let columns: [GridItem] = [
            GridItem(.flexible(minimum: 0), spacing: 12),
            GridItem(.flexible(minimum: 0), spacing: 12)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(allChains.enumerated()), id: \.offset) { _, chain in
                ChainListItem(chainName: chain.0, chainId: chain.1)
            }
        }
    }
}

struct SwiftUINetworkIndicator: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "circle.fill").resizable().frame(width: 12, height: 12).foregroundColor(color)

            Text(text).font(.subheadline).foregroundColor(.labelPrimary)
        }
        // shift left to compensate for the dot and spacing so that the text would be centered in the container
        .padding(.leading, -(9 + 12))
    }
}

struct ChainListItem: View {
    let chainName: String
    let chainId: String?
    
    var body: some View {
        HStack(spacing: 10) {
            // Chain icon
            if let chainId = chainId, let image = UIImage(named: "ico-chain-\(chainId)") {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                // Fallback icon for chains without specific icon (like Plasma)
                Circle()
                    .fill(Color.icon.opacity(0.3))
                    .frame(width: 28, height: 28)
            }
            
            // Chain name and time
            VStack(alignment: .leading, spacing: 4) {
                Text(chainName)
                    .font(.headline)
                    .foregroundColor(.labelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                
                Text("5 min")
                    .font(.subheadline)
                    .foregroundColor(.labelSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

struct WhatsAppLinkView: View {
    var body: some View {
        Button(action: {
            PublicConfigService.shared.getWhatsAppSupportConfig { phoneNumber, message in
                let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
                if let url = URL(string: "https://wa.me/\(phoneNumber)?text=\(encodedMessage)") {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }) {
            Text("Para TRON, BITCOIN u otras redes, contáctanos")
                .font(.subheadline)
                .foregroundColor(.primary)
                .underline()
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

struct SafeInfoContentView_Previews: PreviewProvider {
    static var previews: some View {
        SafeInfoContentView(safe: Safe())
        .padding()
    }
}
