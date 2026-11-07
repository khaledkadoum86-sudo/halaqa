import UIKit
import UniformTypeIdentifiers

/// امتداد المشاركة: يُظهر «خزانتي» في قائمة المشاركة لتطبيق «جهات الاتصال».
/// يأخذ بطاقة الجهة (vCard) ويفتح «خزانتي» بها مباشرة، فتدخل قسم «جهاتي».
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
        label.text = "جارٍ إرسال الجهة إلى خزانتي…"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        collect { [weak self] text in
            DispatchQueue.main.async { self?.deliver(text) }
        }
    }

    /// يجمع كل بطاقات vCard المرسلة في نص واحد.
    private func collect(_ done: @escaping (String) -> Void) {
        let vcard = "public.vcard"
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(vcard) }
        var parts: [String] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: vcard, options: nil) { item, _ in
                var data: Data?
                if let d = item as? Data { data = d }
                else if let u = item as? URL { data = try? Data(contentsOf: u) }
                else if let s = item as? String { data = s.data(using: .utf8) }
                if let d = data, let s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .utf16) {
                    lock.lock(); parts.append(s); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .global()) { done(parts.joined(separator: "\n")) }
    }

    /// يحذف الصور من البطاقة (فهي كبيرة ولا تُحفظ في الخزانة) ثم يفتح «خزانتي» بها.
    private func deliver(_ text: String) {
        guard !text.isEmpty else { finish("لم أجد بطاقة جهة اتصال."); return }
        var lines: [String] = []
        var inPhoto = false
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if inPhoto { if raw.hasPrefix(" ") || raw.hasPrefix("\t") { continue } else { inPhoto = false } }
            if raw.uppercased().hasPrefix("PHOTO") { inPhoto = true; continue }
            lines.append(raw)
        }
        let clean = lines.joined(separator: "\r\n")
        let b64 = Data(clean.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        guard let url = URL(string: "khizana://contact?d=" + b64), openApp(url) else {
            UIPasteboard.general.string = clean
            finish("نُسخت الجهة. افتح «خزانتي» ← «جهاتي» ← «لصق جهة منسوخة».")
            return
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// فتح التطبيق الأصلي من الامتداد عبر سلسلة المستجيبات (دون واجهات ممنوعة على الامتدادات).
    private func openApp(_ url: URL) -> Bool {
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if r is UIApplication, r.responds(to: sel) {
                _ = r.perform(sel, with: url, with: NSDictionary())
                return true
            }
            responder = r.next
        }
        return false
    }

    private func finish(_ message: String) {
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
