import SwiftUI

/// «سجل متابعة الطلبة» as a native iPhone / iPad app.
/// The app shows the same web app that lives on GitHub Pages, so every update reaches it by itself.
/// After the first launch it also opens without internet (the page is kept on the device).
@main
struct HalaqaApp: App {
    init() { RenewalReminder.schedule() }   // تذكير التجديد قبل انتهاء الأيام السبعة

    var body: some Scene {
        WindowGroup {
            WebContainer()
                .onOpenURL { BookInbox.shared.receive($0) }   // PDF shared from another app → «الخزانة العلمية»
                .ignoresSafeArea()
                .background(Color(red: 0.96, green: 0.97, blue: 0.98).ignoresSafeArea())
        }
    }
}

struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}
