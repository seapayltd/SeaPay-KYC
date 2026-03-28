//
//  AppIntent.swift
//  Expiry Widget
//
//  No configuration needed — the widget auto-reads expiry data.
//

import WidgetKit
import AppIntents

struct ExpiryWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "OceanCheck Expiry" }
    static var description: IntentDescription { "Shows document and certificate expiry status." }
}
