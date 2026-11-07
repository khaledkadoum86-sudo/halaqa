import SwiftUI
import UserNotifications

/// «خزانتي» تطبيقًا أصليًّا للآيفون والآيباد.
/// يعرض صفحة «خزانتي» التي على GitHub Pages، فكل تحديث يصل إليه وحده،
/// ويستقبل أي ملف يُشارَك إليه من تطبيق آخر (واتساب، الملفات، الصور، تيليغرام…).
@main
struct KhizanaApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = Banner.shared   // التنبيهات تظهر والتطبيق مفتوح أيضًا
        RenewalReminder.schedule()   // تذكير التجديد قبل انتهاء الأيام السبعة
    }

    var body: some Scene {
        WindowGroup {
            WebContainer()
                .onOpenURL { Inbox.shared.receive($0) }   // ملف وصل من قائمة المشاركة
                .ignoresSafeArea()
                .overlay(RenewalIndicator(appName: "خزانتي", current: "khizana"))   // زر «تطبيقاتي» العائم وعدّاد أيام التجديد
                .background(Color(red: 0.961, green: 0.969, blue: 0.980).ignoresSafeArea())
        }
    }
}

struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}

/// يُظهر التنبيه (مثل «وصل إلى خزانتي») حتى والتطبيق في الواجهة، ويستدعي الصفحة لتأخذ ما وصل.
final class Banner: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Banner()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier.hasPrefix("khizana-box") { NotificationCenter.default.post(name: Inbox.arrived, object: nil) }
        if #available(iOS 14.0, *) { done([.banner, .list, .sound]) } else { done([.alert, .sound]) }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        NotificationCenter.default.post(name: Inbox.arrived, object: nil)
        done()
    }
}
