//
//  NotificationService.swift
//  OceanCheck
//
//  Schedules local push notifications for document expiry.
//  90, 30, 7, 1 day warnings. Respects iOS 64-notification limit.
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
        var count = 0
        let limit = 60 // leave 4 slots for system

        // Crew ID document expiry
        for check in checks {
            guard count < limit else { return }
            if let expStr = check.expiryDate, let exp = dateFmt.date(from: expStr) {
                count += schedule(exp: exp, title: check.customerName, subtitle: "ID Document", id: check.id, count: &count, limit: limit)
            }
            // Crew documents
            for doc in check.documents ?? [] where doc.expiryDate != nil && !doc.isArchived {
                guard count < limit else { return }
                count += schedule(exp: doc.expiryDate!, title: check.customerName, subtitle: doc.displayName, id: "\(check.id)_\(doc.id)", count: &count, limit: limit)
            }
        }

        // Vessel documents
        for vessel in vessels {
            for doc in vessel.documents ?? [] where doc.expiryDate != nil && !doc.isArchived {
                guard count < limit else { return }
                count += schedule(exp: doc.expiryDate!, title: vessel.name, subtitle: doc.displayName, id: "\(vessel.id)_\(doc.id)", count: &count, limit: limit)
            }
        }
    }

    @discardableResult
    private func schedule(exp: Date, title: String, subtitle: String, id: String, count: inout Int, limit: Int) -> Int {
        var added = 0
        // Prioritize closer warnings
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
        // Schedule at 9 AM
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }
}
