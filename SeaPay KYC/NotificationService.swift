//
//  NotificationService.swift
//  OceanCheck
//
//  Schedules local push notifications for document expiry.
//  Priority-based: vessel certs + crew IDs first, then by urgency (sooner = higher priority).
//  Respects iOS 64-notification limit.
//

import Foundation
import UserNotifications

@MainActor
class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func rescheduleAll(checks: [KYCCheck], vessels: [Vessel]) {
        center.removeAllPendingNotificationRequests()

        // Collect all expiring items with priority
        struct ExpiryItem {
            let expiry: Date
            let title: String
            let subtitle: String
            let id: String
            let priority: Int // 0 = highest (vessel cert/crew ID), 1 = crew doc
        }

        var items: [ExpiryItem] = []

        // Vessel certificates — highest priority
        for vessel in vessels {
            for doc in vessel.documents ?? [] where doc.expiryDate != nil && !doc.isArchived {
                guard let exp = doc.expiryDate else { continue }
                items.append(ExpiryItem(expiry: exp, title: vessel.name, subtitle: doc.displayName, id: "\(vessel.id)_\(doc.id)", priority: 0))
            }
        }

        // Crew ID expiry — highest priority
        for check in checks {
            if let expStr = check.expiryDate, let exp = dateFmt.date(from: expStr) {
                items.append(ExpiryItem(expiry: exp, title: check.customerName, subtitle: "ID Document", id: check.id, priority: 0))
            }
        }

        // Crew documents — lower priority
        for check in checks {
            for doc in check.documents ?? [] where doc.expiryDate != nil && !doc.isArchived {
                guard let exp = doc.expiryDate else { continue }
                items.append(ExpiryItem(expiry: exp, title: check.customerName, subtitle: doc.displayName, id: "\(check.id)_\(doc.id)", priority: 1))
            }
        }

        // Sort: priority first, then by expiry date (sooner = first)
        items.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.expiry < b.expiry
        }

        // Schedule with limit
        var count = 0
        let limit = 60

        for item in items {
            guard count < limit else { break }
            count += schedule(exp: item.expiry, title: item.title, subtitle: item.subtitle, id: item.id, count: &count, limit: limit)
        }
    }

    @discardableResult
    private func schedule(exp: Date, title: String, subtitle: String, id: String, count: inout Int, limit: Int) -> Int {
        var added = 0
        for days in [1, 7, 30, 90] {
            guard count + added < limit else { break }
            guard let trigger = triggerDate(daysBefore: days, expiry: exp) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(subtitle) expiring"
            content.body = "\(title) — \(subtitle) expires in \(days) day\(days == 1 ? "" : "s")"
            content.sound = .default
            content.userInfo = ["id": id]

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: trigger)
            let req = UNNotificationRequest(
                identifier: "\(id)_\(days)d",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            center.add(req)
            added += 1
        }
        return added
    }

    private func triggerDate(daysBefore: Int, expiry: Date) -> Date? {
        let date = Calendar.current.date(byAdding: .day, value: -daysBefore, to: expiry)
        guard let date, date > Date() else { return nil }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }
}
