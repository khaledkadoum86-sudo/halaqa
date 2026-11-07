import UIKit
import WebKit
import QuickLook
import PDFKit
import Vision
import LocalAuthentication
import ContactsUI
import Contacts

let appURL = URL(string: "https://khaledkadoum86-sudo.github.io/halaqa/khizana/")!
let appHost = "khaledkadoum86-sudo.github.io"
private let pageBackground = UIColor(red: 0.961, green: 0.969, blue: 0.980, alpha: 1)

/// صفحة «خزانتي» داخل التطبيق، مع ثلاث خدمات أصلية:
/// استقبال الملفات من قائمة المشاركة، وعرض الملفات بـ Quick Look، وحفظ النسخ الاحتياطية عبر قائمة المشاركة.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandlerWithReply, QLPreviewControllerDataSource {
    private var webView: WKWebView!
    private var offlineView: UIView?
    private var downloads: [ObjectIdentifier: URL] = [:]
    private var preview: PreviewItem?

    override func loadView() {
        let config = WKWebViewConfiguration()
        // النطاقات المعتمدة: تسمح للصفحة أن تحفظ نفسها في الجهاز (Service Worker) فتعمل دون إنترنت
        config.limitsNavigationsToAppBoundDomains = true
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.applicationNameForUserAgent = "Mobile/15E148 KhizanaApp"

        let content = config.userContentController
        content.addUserScript(WKUserScript(source: "window.KHIZANA_NATIVE=true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addScriptMessageHandler(self, contentWorld: .page, name: "khizanaFile")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = pageBackground
        webView.scrollView.backgroundColor = pageBackground
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: appURL))
        NotificationCenter.default.addObserver(self, selector: #selector(pokePage), name: Inbox.arrived, object: nil)
    }

    /// يخبر الصفحة أن ملفًا وصل، فتطلبه قطعة قطعة.
    @objc private func pokePage() {
        webView.evaluateJavaScript("window.khizanaPoll && khizanaPoll()", completionHandler: nil)
    }

    // MARK: - window.webkit.messageHandlers.khizanaFile

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        let body = message.body as? [String: Any] ?? [:]
        let id = body["id"] as? String ?? ""
        let index = (body["i"] as? NSNumber)?.intValue ?? 0
        switch body["action"] as? String ?? "" {
        case "pending":
            replyHandler(Inbox.shared.pending(), nil)
        case "read":
            replyHandler(Inbox.shared.piece(id, index: index), nil)
        case "done":
            Inbox.shared.drop(id)
            replyHandler(true, nil)
        case "chunk":
            // الصفحة ترسل الملف قطعًا لعرضه بـ Quick Look
            let part = Viewer.partURL(for: id)
            guard let s = body["s"] as? String, let data = Data(base64Encoded: s) else { replyHandler(false, nil); return }
            if index == 0 {
                replyHandler(FileManager.default.createFile(atPath: part.path, contents: data), nil)
            } else if let handle = try? FileHandle(forWritingTo: part) {
                handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
                replyHandler(true, nil)
            } else { replyHandler(false, nil) }
        case "analyze":
            // قراءة الملف في الجهاز: عدد الصفحات وبيانات الكتاب ونصّ أوله (وقراءة الصور بالتعرّف على النص)
            let name = body["name"] as? String ?? ""
            let fromInbox = (body["src"] as? String) == "inbox"
            let file = fromInbox ? Inbox.shared.fileURL(id) : Viewer.partURL(for: id)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Analyzer.analyze(file, name: name)
                if !fromInbox { try? FileManager.default.removeItem(at: file) }
                DispatchQueue.main.async { replyHandler(result, nil) }
            }
        case "show":
            let name = body["name"] as? String ?? "ملف"
            let file = Viewer.fileURL(for: id, name: name)
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? FileManager.default.moveItem(at: Viewer.partURL(for: id), to: file)) != nil else { replyHandler(false, nil); return }
            show(file, title: name)
            replyHandler(true, nil)
        case "pickContacts":
            // اختيار جهات من «جهات الاتصال» في الآيفون (لا يحتاج إذنًا)، وتعود بصيغة vCard
            ContactPicker.shared.present(from: self) { replyHandler($0, nil) }
        case "contactsScan":
            // قراءة كل جهات الاتصال (يطلب الإذن أول مرة) لتبحث الصفحة عن المكرر
            ContactsCleaner.scan { replyHandler($0, nil) }
        case "contactsBackup":
            // نسخة كاملة من جهات الاتصال بصيغة vCard في ملف مؤقت، تقرؤه الصفحة قطعة قطعة وتحفظه قبل أي حذف
            ContactsCleaner.backup { replyHandler($0, nil) }
        case "contactsBackupPiece":
            replyHandler(ContactsCleaner.backupPiece(index), nil)
        case "contactsBackupDone":
            try? FileManager.default.removeItem(at: ContactsCleaner.backupFile)
            replyHandler(true, nil)
        case "contactsMerge":
            // دمج كل مجموعة في الجهة الباقية ثم حذف المكرر منها
            ContactsCleaner.merge(body["groups"] as? [[String: Any]] ?? []) { replyHandler($0, nil) }
        case "openSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            replyHandler(true, nil)
        case "biometry":
            // نوع القفل المتاح في الجهاز: faceID أو touchID أو none
            let ctx = LAContext()
            var err: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { replyHandler("none", nil); return }
            replyHandler(ctx.biometryType == .faceID ? "faceID" : ctx.biometryType == .touchID ? "touchID" : "none", nil)
        case "auth":
            // فتح القفل ببصمة الوجه (أو رمز الجهاز إن تعذّرت البصمة)
            let ctx = LAContext()
            ctx.localizedCancelTitle = "إلغاء"
            ctx.localizedFallbackTitle = "رمز الجهاز"
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: body["reason"] as? String ?? "لفتح خزانتي") { ok, _ in
                DispatchQueue.main.async { replyHandler(ok, nil) }
            }
        default:
            replyHandler(nil, nil)
        }
    }

    private func show(_ file: URL, title: String) {
        preview = PreviewItem(url: file, title: title)
        let controller = QLPreviewController()   // فيه زر المشاركة لفتح الملف في تطبيق آخر
        controller.dataSource = self
        controller.modalPresentationStyle = .fullScreen
        top().present(controller, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { preview == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { preview! }

    // MARK: - الروابط: التطبيق يبقى في مكانه، وواتساب والهاتف والمواقع الأخرى تُفتح خارجه

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = (url.scheme ?? "").lowercased()
        if ["blob", "data", "about"].contains(scheme) { decisionHandler(.allow); return }
        if Siblings.handle(url) { decisionHandler(.cancel); return }   // halaqa:// khizana:// mawrid://
        if scheme == "https" && url.host == appHost && url.path.contains("/khizana") { decisionHandler(.allow); return }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, (url.scheme ?? "") != "blob" { UIApplication.shared.open(url) }
        return nil
    }

    // MARK: - ما تحفظه الصفحة (نسخ احتياطية، ملفات) ← قائمة المشاركة

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(suggestedFilename.isEmpty ? "ملف" : suggestedFilename)
        downloads[ObjectIdentifier(download)] = file
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top().present(sheet, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
    }

    // MARK: - alert / confirm / prompt

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "حسنًا", style: .default) { _ in completionHandler() })
        top().present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(true) })
        top().present(alert, animated: true)
    }

    // MARK: - لا إنترنت عند أول تشغيل

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let code = (error as NSError).code
        if code == NSURLErrorCancelled || code == 102 { return }
        if webView.url == nil || webView.url?.host != appHost || !webView.canGoBack { showOffline() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        offlineView?.removeFromSuperview()
        offlineView = nil
        pokePage()   // ملفات وصلت والتطبيق مغلق
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    private func showOffline() {
        guard offlineView == nil else { return }
        let box = UIView(frame: view.bounds)
        box.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.backgroundColor = pageBackground

        let label = UILabel()
        label.text = "لا يوجد اتصال بالإنترنت.\nيحتاج التطبيق إلى الإنترنت عند أول تشغيل فقط، ثم يعمل دونه."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = UIColor(red: 0.11, green: 0.16, blue: 0.21, alpha: 1)

        let button = UIButton(type: .system)
        button.setTitle("إعادة المحاولة", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.addTarget(self, action: #selector(retry), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -28),
        ])
        view.addSubview(box)
        offlineView = box
    }

    @objc private func retry() {
        offlineView?.removeFromSuperview()
        offlineView = nil
        webView.load(URLRequest(url: appURL))
    }

    private func top() -> UIViewController {
        var controller: UIViewController = self
        while let next = controller.presentedViewController { controller = next }
        return controller
    }
}

// MARK: - الملفات الواردة من قائمة المشاركة

/// أي ملف يُفتح في «خزانتي» من تطبيق آخر ينتظر في Caches/inbox حتى تأخذه الصفحة.
/// وما يتركه iOS في Documents/Inbox يُلتقط أيضًا، فلا يضيع شيء إن انقطع التسليم.
final class Inbox {
    static let shared = Inbox()
    static let arrived = Notification.Name("KhizanaFileArrived")
    static let step = 393_216   // مضاعف للعدد 3، فكل قطعة base64 صحيحة وحدها

    private let fm = FileManager.default
    private var folder: URL {
        let f = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("inbox", isDirectory: true)
        try? fm.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }

    func receive(_ url: URL) {
        if url.scheme == "khizana" { if takeBox() > 0 || takeContact(url) || takeNote(url) { NotificationCenter.default.post(name: Inbox.arrived, object: nil) }; return }
        if take(url) { NotificationCenter.default.post(name: Inbox.arrived, object: nil) }
    }

    @discardableResult private func take(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let id = "f" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 1296...46655), radix: 36)
        do { try fm.copyItem(at: url, to: folder.appendingPathComponent(id + ".bin")) } catch { return false }
        try? url.lastPathComponent.write(to: folder.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
        if url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
        return true
    }

    /// الملفات التي وضعها امتداد المشاركة في الصندوق المشترك (لوحة نسخ مسمّاة لحساب المطوّر نفسه).
    @discardableResult func takeBox() -> Int {
        guard let box = UIPasteboard(name: UIPasteboard.Name("com.khaledkadoum.khizana.box"), create: false), box.numberOfItems > 0 else { return 0 }
        var n = 0
        for item in box.items {
            guard let data = item["com.khaledkadoum.khizana.file"] as? Data else { continue }
            let rawName = (item["com.khaledkadoum.khizana.name"] as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "ملف"
            let name = String(rawName.filter { !"/\\:".contains($0) }.prefix(120))
            let id = "b" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 1296...46655), radix: 36) + String(n)
            guard fm.createFile(atPath: folder.appendingPathComponent(id + ".bin").path, contents: data) else { continue }
            try? name.write(to: folder.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
            n += 1
        }
        box.items = []
        return n
    }

    /// جهة اتصال وصلت من امتداد المشاركة: khizana://contact?d=<vCard بترميز base64url>
    private func takeContact(_ url: URL) -> Bool {
        guard url.host == "contact",
              var d = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value else { return false }
        d = d.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while d.count % 4 != 0 { d += "=" }
        guard let data = Data(base64Encoded: d) else { return false }
        let id = "c" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 1296...46655), radix: 36)
        guard fm.createFile(atPath: folder.appendingPathComponent(id + ".bin").path, contents: data) else { return false }
        try? "جهة اتصال.vcf".write(to: folder.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
        return true
    }

    /// مذكرة وصلت من «مورد الظمآن»: khizana://note?name=<العنوان>&d=<النص بترميز base64url>
    private func takeNote(_ url: URL) -> Bool {
        guard url.host == "note", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              var d = items.first(where: { $0.name == "d" })?.value else { return false }
        d = d.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while d.count % 4 != 0 { d += "=" }
        guard let data = Data(base64Encoded: d) else { return false }
        let title = String((items.first(where: { $0.name == "name" })?.value ?? "مذكرة").filter { !"/\\:".contains($0) }.prefix(80))
        let id = "n" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 1296...46655), radix: 36)
        guard fm.createFile(atPath: folder.appendingPathComponent(id + ".bin").path, contents: data) else { return false }
        try? (title + ".txt").write(to: folder.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
        return true
    }

    func pending() -> [[String: Any]] {
        takeBox()
        let systemInbox = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Inbox", isDirectory: true)
        for f in (try? fm.contentsOfDirectory(at: systemInbox, includingPropertiesForKeys: nil)) ?? [] { take(f) }
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.pathExtension == "bin" }.map { f in
            let id = f.deletingPathExtension().lastPathComponent
            let name = (try? String(contentsOf: folder.appendingPathComponent(id + ".name"), encoding: .utf8)) ?? "ملف"
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return ["id": id, "name": name, "size": size]
        }
    }

    private static func safe(_ id: String) -> String { String(id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40)) }

    func fileURL(_ id: String) -> URL { folder.appendingPathComponent(Inbox.safe(id) + ".bin") }

    /// القطعة رقم index من الملف بترميز base64، أو "" بعد آخر قطعة.
    func piece(_ id: String, index: Int) -> String {
        let file = folder.appendingPathComponent(Inbox.safe(id) + ".bin")
        guard index >= 0, let h = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { h.closeFile() }
        h.seek(toFileOffset: UInt64(index) * UInt64(Inbox.step))
        return h.readData(ofLength: Inbox.step).base64EncodedString()
    }

    func drop(_ id: String) {
        let safe = Inbox.safe(id)
        for ext in ["bin", "name"] { try? fm.removeItem(at: folder.appendingPathComponent(safe + "." + ext)) }
    }
}

/// نسخة مؤقتة من الملف المفتوح، ليعرضه Quick Look باسمه الحقيقي.
enum Viewer {
    static var folder: URL {
        let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("view", isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }
    static func safe(_ id: String) -> String { String(id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40)) }
    static func partURL(for id: String) -> URL { folder.appendingPathComponent(safe(id) + ".part") }
    static func fileURL(for id: String, name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "-")
        return folder.appendingPathComponent(safe(id), isDirectory: true).appendingPathComponent(clean.isEmpty ? "ملف" : clean)
    }
}

final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL, title: String) { previewItemURL = url; previewItemTitle = title }
}

// MARK: - قراءة الملف للتصنيف (في الجهاز، لا يخرج شيء منه)

enum Analyzer {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp"]

    static func analyze(_ file: URL, name: String) -> [String: Any] {
        let ext = (name as NSString).pathExtension.lowercased()
        var out: [String: Any] = ["text": "", "pages": 0, "title": "", "author": "", "ocr": false]
        if ext == "pdf", let doc = PDFDocument(url: file) {
            out["pages"] = doc.pageCount
            let attrs = doc.documentAttributes ?? [:]
            out["title"] = (attrs[PDFDocumentAttribute.titleAttribute] as? String) ?? ""
            out["author"] = (attrs[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
            var text = ""
            for i in 0..<min(doc.pageCount, 4) { text += (doc.page(at: i)?.string ?? "") + "\n" }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40, let page = doc.page(at: 0) {
                // PDF مصوَّر: نقرأ الصفحة الأولى بالتعرّف على النص
                let image = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox)
                if let cg = image.cgImage { text = ocr(cg); out["ocr"] = true }
            }
            out["text"] = String(text.prefix(5000))
        } else if imageExts.contains(ext), let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            let small = WebViewController.fit(image, longest: 2000)
            if let cg = small.cgImage { out["text"] = String(ocr(cg).prefix(3000)); out["ocr"] = true }
        } else if ["txt", "md", "csv"].contains(ext), let t = try? String(contentsOf: file, encoding: .utf8) {
            out["text"] = String(t.prefix(5000))
        }
        return out
    }

    static func ocr(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let langs = ["ar-SA", "ars-SA", "fr-FR", "en-US"].filter { supported.contains($0) }
        if !langs.isEmpty { request.recognitionLanguages = langs }
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

extension WebViewController {
    static func fit(_ image: UIImage, longest: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > longest else { return image }
        let scale = longest / side
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}


/// نافذة اختيار جهات الاتصال من الآيفون، تعيد البطاقات المختارة نصًّا بصيغة vCard (أو nil عند الإلغاء).
final class ContactPicker: NSObject, CNContactPickerDelegate {
    static let shared = ContactPicker()
    private var done: ((String?) -> Void)?

    func present(from vc: UIViewController, done: @escaping (String?) -> Void) {
        self.done?(nil)
        self.done = done
        let picker = CNContactPickerViewController()
        picker.delegate = self
        var top = vc
        while let p = top.presentedViewController { top = p }
        top.present(picker, animated: true)
    }

    private func finish(_ text: String?) { let d = done; done = nil; d?(text) }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) { finish(nil) }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
        guard let data = try? CNContactVCardSerialization.data(with: contacts) else { finish(nil); return }
        finish(String(data: data, encoding: .utf8))
    }
}


/// تنظيف جهات الاتصال المكررة في الآيفون: القراءة، والنسخ الاحتياطي، والدمج ثم الحذف.
/// الصفحة هي التي تقرّر ما المكرر وما يبقى، وهذا الجزء ينفّذ فقط بعد موافقة المستخدم.
enum ContactsCleaner {
    private static let store = CNContactStore()
    private static let work = DispatchQueue(label: "khizana.contacts", qos: .userInitiated)

    /// "full" أو "limited" (سمح ببعض الجهات فقط) أو "denied"
    private static func access(_ done: @escaping (String) -> Void) {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { done("full"); return }
        if status.rawValue == 4 { done("limited"); return }   // الوصول المحدود (iOS 18)
        if status == .notDetermined {
            store.requestAccess(for: .contacts) { _, _ in
                let now = CNContactStore.authorizationStatus(for: .contacts)
                done(now == .authorized ? "full" : now.rawValue == 4 ? "limited" : "denied")
            }
            return
        }
        done("denied")
    }

    private static let mergeKeys: [CNKeyDescriptor] = ([
        CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey, CNContactNicknameKey,
        CNContactOrganizationNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        CNContactPostalAddressesKey, CNContactUrlAddressesKey, CNContactBirthdayKey, CNContactImageDataKey,
        CNContactImageDataAvailableKey
    ] as [CNKeyDescriptor]) + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]

    /// للفحص: دون الصور حتى يبقى خفيفًا ولو كانت الجهات بالآلاف
    private static let scanKeys: [CNKeyDescriptor] = ([
        CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        CNContactPostalAddressesKey, CNContactUrlAddressesKey, CNContactBirthdayKey, CNContactImageDataAvailableKey
    ] as [CNKeyDescriptor]) + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]

    static func scan(_ done: @escaping ([String: Any]) -> Void) {
        access { state in
            guard state != "denied" else { DispatchQueue.main.async { done(["status": state, "list": []]) }; return }
            work.async {
                var list: [[String: Any]] = []
                let request = CNContactFetchRequest(keysToFetch: scanKeys)
                request.sortOrder = .userDefault
                do { try store.enumerateContacts(with: request) { c, _ in
                    let name = CNContactFormatter.string(from: c, style: .fullName) ?? ""
                    list.append([
                        "id": c.identifier,
                        "name": name,
                        "org": c.organizationName,
                        "phones": c.phoneNumbers.map { $0.value.stringValue },
                        "emails": c.emailAddresses.map { $0.value as String },
                        "extra": c.postalAddresses.count + c.urlAddresses.count + (c.birthday == nil ? 0 : 1),
                        "photo": c.imageDataAvailable
                    ])
                } } catch { DispatchQueue.main.async { done(["status": "error", "list": []]) }; return }
                DispatchQueue.main.async { done(["status": state, "list": list]) }
            }
        }
    }

    static var backupFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("contacts-backup.vcf")
    }

    /// يكتب كل الجهات (بصورها) في ملف vCard مؤقت ← {count, size}، أو nil إن تعذّر
    static func backup(_ done: @escaping ([String: Any]?) -> Void) {
        access { state in
            guard state != "denied" else { DispatchQueue.main.async { done(nil) }; return }
            work.async {
                var all: [CNContact] = []
                let request = CNContactFetchRequest(keysToFetch: [CNContactVCardSerialization.descriptorForRequiredKeys()])
                do {
                    try store.enumerateContacts(with: request) { c, _ in all.append(c) }
                    let data = try CNContactVCardSerialization.data(with: all)
                    try data.write(to: backupFile, options: .atomic)
                    DispatchQueue.main.async { done(["count": all.count, "size": data.count]) }
                } catch { DispatchQueue.main.async { done(nil) } }
            }
        }
    }

    /// القطعة رقم index من ملف النسخة بترميز base64، أو "" بعد آخر قطعة
    static func backupPiece(_ index: Int) -> String {
        guard index >= 0, let h = try? FileHandle(forReadingFrom: backupFile) else { return "" }
        defer { h.closeFile() }
        h.seek(toFileOffset: UInt64(index) * UInt64(Inbox.step))
        return h.readData(ofLength: Inbox.step).base64EncodedString()
    }

    private static func digits(_ s: String) -> String {
        let d = s.filter { $0.isNumber }.map { String($0) }.joined()
        return String(d.suffix(9))
    }

    /// groups: [{keep: id, remove: [id]}] ← {merged, deleted, failed}
    static func merge(_ groups: [[String: Any]], _ done: @escaping ([String: Any]) -> Void) {
        access { state in
            guard state != "denied" else { DispatchQueue.main.async { done(["merged": 0, "deleted": 0, "failed": groups.count]) }; return }
            work.async {
                var merged = 0, deleted = 0, failed = 0
                for g in groups {
                    guard let keepId = g["keep"] as? String, let removeIds = g["remove"] as? [String], !removeIds.isEmpty else { failed += 1; continue }
                    do {
                        let keep = try store.unifiedContact(withIdentifier: keepId, keysToFetch: mergeKeys).mutableCopy() as! CNMutableContact
                        let others = try store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: removeIds), keysToFetch: mergeKeys)
                        guard !others.isEmpty else { failed += 1; continue }
                        var phones = Set(keep.phoneNumbers.map { digits($0.value.stringValue) })
                        var emails = Set(keep.emailAddresses.map { ($0.value as String).lowercased() })
                        var places = Set(keep.postalAddresses.map { CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress) })
                        var urls = Set(keep.urlAddresses.map { ($0.value as String).lowercased() })
                        for o in others {
                            for p in o.phoneNumbers {
                                let d = digits(p.value.stringValue)
                                if !d.isEmpty && !phones.contains(d) { phones.insert(d); keep.phoneNumbers.append(CNLabeledValue(label: p.label, value: p.value)) }
                            }
                            for e in o.emailAddresses {
                                let k = (e.value as String).lowercased()
                                if !emails.contains(k) { emails.insert(k); keep.emailAddresses.append(CNLabeledValue(label: e.label, value: e.value)) }
                            }
                            for a in o.postalAddresses {
                                let k = CNPostalAddressFormatter.string(from: a.value, style: .mailingAddress)
                                if !places.contains(k) { places.insert(k); keep.postalAddresses.append(CNLabeledValue(label: a.label, value: a.value)) }
                            }
                            for u in o.urlAddresses {
                                let k = (u.value as String).lowercased()
                                if !urls.contains(k) { urls.insert(k); keep.urlAddresses.append(CNLabeledValue(label: u.label, value: u.value)) }
                            }
                            if keep.givenName.isEmpty && keep.familyName.isEmpty { keep.givenName = o.givenName; keep.familyName = o.familyName; keep.middleName = o.middleName }
                            if keep.organizationName.isEmpty { keep.organizationName = o.organizationName }
                            if keep.jobTitle.isEmpty { keep.jobTitle = o.jobTitle }
                            if keep.nickname.isEmpty { keep.nickname = o.nickname }
                            if keep.birthday == nil { keep.birthday = o.birthday }
                            if keep.imageData == nil, let img = o.imageData { keep.imageData = img }
                        }
                        let save = CNSaveRequest()
                        save.update(keep)
                        for o in others { save.delete(o.mutableCopy() as! CNMutableContact) }
                        try store.execute(save)
                        merged += 1; deleted += others.count
                    } catch { failed += 1 }
                }
                DispatchQueue.main.async { done(["merged": merged, "deleted": deleted, "failed": failed]) }
            }
        }
    }
}
