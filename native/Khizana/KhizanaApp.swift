import SwiftUI

/// «خزانتي» تطبيقًا أصليًّا للآيفون والآيباد.
/// يعرض صفحة «خزانتي» التي على GitHub Pages، فكل تحديث يصل إليه وحده،
/// ويستقبل أي ملف يُشارَك إليه من تطبيق آخر (واتساب، الملفات، الصور، تيليغرام…).
@main
struct KhizanaApp: App {
    init() { RenewalReminder.schedule() }   // تذكير التجديد قبل انتهاء الأيام السبعة

    var body: some Scene {
        WindowGroup {
            WebContainer()
                .onOpenURL { Inbox.shared.receive($0) }   // ملف وصل من قائمة المشاركة
                .ignoresSafeArea()
                .background(Color(red: 0.95, green: 0.96, blue: 0.96).ignoresSafeArea())
        }
    }
}

struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}
