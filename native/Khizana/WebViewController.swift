import UIKit
import WebKit
import QuickLook

let appURL = URL(string: "https://khaledkadoum86-sudo.github.io/halaqa/khizana/")!
let appHost = "khaledkadoum86-sudo.github.io"
private let pageBackground = UIColor(red: 0.95, green: 0.96, blue: 0.96, alpha: 1)

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
        case "show":
            let name = body["name"] as? String ?? "ملف"
            let file = Viewer.fileURL(for: id, name: name)
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? FileManager.default.moveItem(at: Viewer.partURL(for: id), to: file)) != nil else { replyHandler(false, nil); return }
            show(file, title: name)
            replyHandler(true, nil)
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

    func pending() -> [[String: Any]] {
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
