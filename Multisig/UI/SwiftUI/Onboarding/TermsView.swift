//
//  TermsView.swift
//  Multisig
//
//  Created by Andrey Scherbovich on 28.05.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import SwiftUI

struct TermsView: View {
    @Binding
    var acceptedTerms: Bool
    
    @Binding
    var isAgreeWithTermsPresented: Bool

    @State
    private var showPrivacyPolicy = false

    @State
    private var showTerms = false

    var onStart: () -> Void

    private let topPadding: CGFloat = Spacing.extraLarge
    private let bottomPadding: CGFloat = Spacing.large
    let interItemSpacing: CGFloat = Spacing.small

    private let termsAndConditionsURL = URL(string: "https://boveda.ai/policy")!

    var body: some View {
        VStack(spacing: interItemSpacing) {
            Text(NSLocalizedString("ui_terms_title", comment: "Terms of Use and Privacy Policy screen title"))
                .headline()
                .multilineTextAlignment(.center)

            VStack(alignment: .leading) {
                BulletText(NSLocalizedString("ui_terms_collect_data", comment: "Data collection explanation"))
                BulletText(NSLocalizedString("ui_terms_no_demographic_data", comment: "No demographic data collection"))
                HStack (spacing: 0) {
                    BulletText(NSLocalizedString("ui_terms_read_more", comment: "Read more prefix text"))
                    LinkButton(NSLocalizedString("ui_terms_conditions_link", comment: "Terms and Conditions link text"), url: termsAndConditionsURL).padding(0)
                }
            }

            Button(NSLocalizedString("ui_terms_get_started", comment: "Get Started button")) {
                agreeWithTerms()
                AppSettings.trackingEnabled = true
            }
            .padding(.bottom)
            .buttonStyle(GNOFilledButtonStyle()).preferredColorScheme(.dark)
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal)
        .background(Color.backgroundSecondary)
        .preferredColorScheme(.light)
        
    }

    private func agreeWithTerms() {
        AppSettings.termsAccepted = true
        self.acceptedTerms = true
        self.onStart()
    }

    struct BulletText: View {
        private let text: String
        private let bulletTopPadding: CGFloat = Spacing.extraSmall

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            HStack(alignment: .top) {
                Image("ico-bullet-point")
                    .foregroundColor(.labelSecondary)
                    .padding(.top, bulletTopPadding)
                Text(text)
                    .body(.labelSecondary)
            }
        }
    }
}

struct TermsView_Previews: PreviewProvider {
    static var previews: some View {
        TermsView(acceptedTerms: .constant(false),
                  isAgreeWithTermsPresented: .constant(true), onStart: {})
    }
}
