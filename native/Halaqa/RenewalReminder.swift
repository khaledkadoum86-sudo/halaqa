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
import SwiftUI
import UIKit

enum RenewalReminder {

    private static let ids = ["halaqa-renew-day-before", "halaqa-renew-same-day"]

    /// استدعِ هذه الدالة مرة واحدة عند تشغيل التطبيق.
    static func schedule() {
        guard let expiry = provisioningExpiry() else { return } // في المحاكي لا يوجد ملف توقيع

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids + badgeIds)
            scheduleBadges(center, expiry: expiry)

            let cal = Calendar.current
            let expiryDay = cal.startOfDay(for: expiry)

            let plan: [(id: String, dayOffset: Int, hour: Int, title: String)] = [
                (ids[0], -1, 10, "صلاحية «المدرسة القرءانية» تنتهي غدًا!"),
                (ids[1],  0,  8, "صلاحية «المدرسة القرءانية» تنتهي اليوم")
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

    // MARK: - عدد الأيام على أيقونة التطبيق

    private static var badgeIds: [String] { (1...7).map { ids[0].replacingOccurrences(of: "day-before", with: "badge-\($0)") } }

    /// الأيام الباقية حتى انتهاء الصلاحية، واليوم الجاري يُحسب يومًا كاملًا (فلا تصير 0 قبل الانتهاء).
    static func daysLeft(_ expiry: Date, now: Date = Date()) -> Int {
        max(0, Int(ceil(expiry.timeIntervalSince(now) / 86_400)))
    }

    /// يضع العدد على الأيقونة الآن، ثم يجدول إشعارات صامتة (دون صوت ولا رسالة) تُنقص العدد كل 24 ساعة
    /// فيبقى الرقم على الأيقونة صحيحًا ولو لم يُفتح التطبيق.
    private static func scheduleBadges(_ center: UNUserNotificationCenter, expiry: Date) {
        setBadge(daysLeft(expiry))
        for k in 1...6 {
            let fire = expiry.addingTimeInterval(-Double(k) * 86_400)
            guard fire > Date().addingTimeInterval(60) else { continue }
            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: k)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSinceNow, repeats: false)
            center.add(UNNotificationRequest(identifier: badgeIds[k - 1], content: content, trigger: trigger))
        }
    }

    static func setBadge(_ n: Int) {
        DispatchQueue.main.async {
            if #available(iOS 16.0, *) { UNUserNotificationCenter.current().setBadgeCount(n) }
            else { UIApplication.shared.applicationIconBadgeNumber = n }
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


// MARK: - مؤشّر التجديد داخل التطبيق

/// نقطة ملوّنة عائمة تعدّ الأيام الباقية للتجديد:
/// أخضر هادئ (4 أيام فأكثر)، برتقالي ينبض (يومان أو ثلاثة)، أحمر يومض (اليوم الأخير).
/// تُسحب إلى أي مكان فتبقى فيه، وبلمسة تُظهر تاريخ الانتهاء وطريقة التجديد.
struct RenewalIndicator: View {
    let appName: String
    private let expiry = RenewalReminder.provisioningExpiry()
    @State private var now = Date()
    @State private var open = false
    @State private var pulse = false
    @State private var drag: CGSize = .zero
    @AppStorage("renewal.y") private var yFraction: Double = 0.36
    @AppStorage("renewal.left") private var onLeft: Bool = true
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var days: Int { expiry.map { RenewalReminder.daysLeft($0, now: now) } ?? 0 }
    private var level: Int { days >= 4 ? 0 : days >= 2 ? 1 : 2 }
    private var tint: Color {
        [Color(red: 0.16, green: 0.62, blue: 0.36), Color(red: 0.95, green: 0.55, blue: 0.10), Color(red: 0.84, green: 0.16, blue: 0.14)][level]
    }
    private var beat: Double { [2.6, 1.3, 0.6][level] }

    var body: some View {
        if expiry != nil {
            GeometryReader { geo in
                ZStack {
                    if open { card.transition(.opacity) }
                    else { dot(in: geo.size) }
                }
                .animation(.easeOut(duration: 0.2), value: open)
            }
            .onReceive(tick) { d in
                let before = days
                now = d
                if days != before { RenewalReminder.setBadge(days); restartPulse() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                now = Date(); RenewalReminder.setBadge(days)
            }
            .onAppear { restartPulse() }
        }
    }

    private func restartPulse() {
        pulse = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: beat).repeatForever(autoreverses: level == 2)) { pulse = true }
        }
    }

    private func dot(in size: CGSize) -> some View {
        let side: CGFloat = 38
        let x = onLeft ? 10 + side / 2 : size.width - 10 - side / 2
        let y = max(70, min(size.height - 110, size.height * yFraction))
        return ZStack {
            Circle().stroke(tint, lineWidth: 3)
                .scaleEffect(pulse ? 1.75 : 1).opacity(pulse ? 0 : (level == 0 ? 0.35 : 0.8))
            Circle().fill(tint)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .opacity(level == 2 && pulse ? 0.4 : 1)
            Text("\(days)").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(.white)
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .position(x: x + drag.width, y: y + drag.height)
        .gesture(DragGesture(minimumDistance: 6)
            .onChanged { drag = $0.translation }
            .onEnded { v in
                onLeft = x + v.translation.width < size.width / 2
                yFraction = Double(max(0.1, min(0.88, (y + v.translation.height) / size.height)))
                withAnimation(.spring()) { drag = .zero }
            })
        .onTapGesture { open = true }
        .accessibilityLabel("باقٍ \(days) أيام على تجديد التطبيق")
    }

    private var phrase: String {
        switch days {
        case 1: return "اليوم الأخير"
        case 2: return "باقٍ يومان"
        case 3...10: return "باقية \(days) أيام"
        default: return "باقٍ \(days) يومًا"
        }
    }

    private var expiryText: String {
        guard let e = expiry else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_DZ@numbers=latn")
        f.dateFormat = "EEEE d MMMM، الساعة HH:mm"
        return f.string(from: e)
    }

    private var card: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { open = false }
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint).frame(width: 64, height: 64)
                    Text("\(days)").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(.white)
                }
                Text("تجديد «\(appName)»").font(.headline)
                Text(phrase).font(.title3.bold()).foregroundColor(tint)
                Text("تنتهي الصلاحية يوم \(expiryText)").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                Text("للتجديد: صِل الآيفون بالماك، وافتح المشروع في Xcode، ثم اضغط ▶. بياناتك تبقى محفوظة، فلا تحذف التطبيق.")
                    .font(.footnote).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("اسحب النقطة إلى أي مكان يناسبك.").font(.caption).foregroundColor(.secondary)
                Button { open = false } label: {
                    Text("حسنًا").bold().frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(tint).foregroundColor(.white).cornerRadius(10)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(UIColor.systemBackground)))
            .shadow(radius: 18)
            .padding(24)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
