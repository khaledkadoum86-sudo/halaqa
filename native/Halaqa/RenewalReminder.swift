//
//  RenewalReminder.swift
//  Halaqa
//
//  تذكير بتجديد التطبيق قبل انتهاء صلاحية التوقيع المجاني (7 أيام).
//  يقرأ تاريخ الانتهاء الحقيقي من ملف التوقيع المضمّن في التطبيق،
//  ثم يجدول إشعارين محليين: صباح اليوم السابق للانتهاء، وصباح يوم الانتهاء.
//  يُعاد حسابهما تلقائيًا بعد كل تجديد (⌘R من Xcode).
//

import Foundation
import UserNotifications

enum RenewalReminder {

    private static let ids = ["halaqa-renew-day-before", "halaqa-renew-same-day"]

    /// استدعِ هذه الدالة مرة واحدة عند تشغيل التطبيق.
    static func schedule() {
        guard let expiry = provisioningExpiry() else { return } // في المحاكي لا يوجد ملف توقيع

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)

            let cal = Calendar.current
            let expiryDay = cal.startOfDay(for: expiry)

            let plan: [(id: String, dayOffset: Int, hour: Int, title: String)] = [
                (ids[0], -1, 10, "صلاحية «سجل الطلبة» تنتهي غدًا!"),
                (ids[1],  0,  8, "صلاحية «سجل الطلبة» تنتهي اليوم")
            ]

            for item in plan {
                guard let day = cal.date(byAdding: .day, value: item.dayOffset, to: expiryDay),
                      let fire = cal.date(bySettingHour: item.hour, minute: 0, second: 0, of: day),
                      fire > Date(), fire < expiry else { continue }

                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = "صِل الهاتف بالماك، افتح المشروع في Xcode واضغط ⌘R لتجديده. بياناتك تبقى محفوظة."
                content.sound = .default

                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }

    /// تاريخ انتهاء ملف التوقيع (embedded.mobileprovision) المضمّن في التطبيق.
    static func provisioningExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<?xml"),
              let end = raw.range(of: "</plist>") else { return nil }

        let xml = String(raw[start.lowerBound..<end.upperBound])
        guard let xmlData = xml.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: xmlData, format: nil) as? [String: Any]
        else { return nil }

        return plist["ExpirationDate"] as? Date
    }
}
