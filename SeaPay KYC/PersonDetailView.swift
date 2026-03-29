//
//  PersonDetailView.swift
//  SeaPay KYC
//
//  Push-destination for crew / person records.
//  Placeholder — Task 5 will build the real implementation.
//

import SwiftUI

struct PersonDetailView: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck

    var body: some View {
        Text(check.displayName)
            .navigationTitle("Person")
    }
}
