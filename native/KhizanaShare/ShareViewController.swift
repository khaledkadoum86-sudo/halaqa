import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// امتداد المشاركة: يُظهر «خزانتي» في قائمة المشاركة لأي ملف (واحد أو عدة ملفات معًا)
/// ولبطاقات جهات الاتصال. يضع الملفات في «صندوق مشترك» بين الامتداد والتطبيق
/// (لوحة النسخ العامة بنوع خاص بخزانتي، تعمل مع الحساب المجاني دون App Groups)،
/// ثم يُظهر تأكيدًا واضحًا ويرسل تنبيهًا، ويفتح «خزانتي» إن أمكن.
final class ShareViewController: UIViewController {
        static let fileType = "com.khaledkadoum.khizana.file"
    static let nameType = "com.khaledkadoum.khizana.name"

    private let icon = UILabel()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.97)
        icon.text = "📥"; icon.font = .systemFont(ofSize: 54); icon.textAlignment = .center
        label.text = "جارٍ الإرسال إلى خزانتي…"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .headline)
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        collect { [weak self] files in DispatchQueue.main.async { self?.deliver(files) } }
    }

    private struct Got { let name: String; let data: Data }

    /// يجمع كل ما أُرسل: ملفات من أي نوع، وبطاقات جهات الاتصال (دون صورها).
    private func collect(_ done: @escaping ([Got]) -> Void) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var out = [Got?](repeating: nil, count: providers.count)
        let group = DispatchGroup()
        for (i, p) in providers.enumerated() {
            group.enter()
            if p.hasItemConformingToTypeIdentifier("public.vcard") {
                p.loadItem(forTypeIdentifier: "public.vcard", options: nil) { item, _ in
                    var d: Data?
                    if let x = item as? Data { d = x } else if let u = item as? URL { d = try? Data(contentsOf: u) } else if let s = item as? String { d = s.data(using: .utf8) }
                    if let d = d, let s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .utf16) {
                        out[i] = Got(name: "جهة اتصال.vcf", data: Data(Self.stripPhotos(s).utf8))
                    }
                    group.leave()
                }
                continue
            }
            let type = p.registeredTypeIdentifiers.first { id in
                guard let t = UTType(id) else { return false }
                return t.conforms(to: .data) || t.conforms(to: .content)
            } ?? "public.data"
            p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                if let url = url, let d = try? Data(contentsOf: url) {
                    var name = p.suggestedName ?? url.lastPathComponent
                    if (name as NSString).pathExtension.isEmpty, let ext = UTType(type)?.preferredFilenameExtension ?? (url.pathExtension.isEmpty ? nil : url.pathExtension) {
                        name += "." + ext
                    }
                    out[i] = Got(name: name, data: d)
                }
                group.leave()
            }
        }
        group.notify(queue: .global()) { done(out.compactMap { $0 }) }
    }

    private func deliver(_ files: [Got]) {
        guard !files.isEmpty else { finish("لم أستطع قراءة ما أُرسل.", ok: false); return }
        // لوحة النسخ العامة: تبقى بعد إغلاق نافذة المشاركة (اللوحة المسمّاة تُمحى عند إغلاقها).
        // نضيف إلى ما لم يأخذه التطبيق بعد، ولا نمسحه.
        let box = UIPasteboard.general
        let old = box.contains(pasteboardTypes: [Self.fileType]) ? box.items.filter { $0[Self.fileType] != nil } : []
        let items: [[String: Any]] = old + files.map { [Self.fileType: $0.data, Self.nameType: Data($0.name.utf8)] }
        box.setItems(items, options: [:])
        guard box.numberOfItems >= files.count else { finish("الملفات كبيرة جدًّا للإرسال دفعة واحدة. أرسلها على دفعات.", ok: false); return }

        let n = files.count
        let what = n == 1 ? "«\(files[0].name)»" : "\(n) ملفات"
        notify(what)
        _ = openApp(URL(string: "khizana://box")!)
        finish("✓ وصل \(what) إلى خزانتي", ok: true)
    }

    /// تنبيه على الآيفون: يظهر حتى لو لم تُفتح «خزانتي».
    private func notify(_ what: String) {
        let c = UNMutableNotificationContent()
        c.title = "📥 وصل إلى خزانتي"
        c.body = what + " — افتح «خزانتي» لترتيبه في مكانه."
        c.sound = .default
        let req = UNNotificationRequest(identifier: "khizana-box-\(Date().timeIntervalSince1970)", content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private static func stripPhotos(_ text: String) -> String {
        var lines: [String] = []; var inPhoto = false
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if inPhoto { if raw.hasPrefix(" ") || raw.hasPrefix("\t") { continue } else { inPhoto = false } }
            if raw.uppercased().hasPrefix("PHOTO") { inPhoto = true; continue }
            lines.append(raw)
        }
        return lines.joined(separator: "\r\n")
    }

    /// فتح التطبيق الأصلي من الامتداد عبر سلسلة المستجيبات.
    private func openApp(_ url: URL) -> Bool {
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if r is UIApplication, r.responds(to: sel) { _ = r.perform(sel, with: url, with: NSDictionary()); return true }
            responder = r.next
        }
        return false
    }

    private func finish(_ message: String, ok: Bool) {
        icon.text = ok ? "✅" : "⚠️"
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 1.6 : 2.6)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
