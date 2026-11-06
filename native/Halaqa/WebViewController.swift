import UIKit
import WebKit
import LocalAuthentication
import QuickLook
import Vision
import VisionKit
import ContactsUI

let appURL = URL(string: "https://khaledkadoum86-sudo.github.io/halaqa/")!
let appHost = "khaledkadoum86-sudo.github.io"
private let pageBackground = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandlerWithReply, QLPreviewControllerDataSource, VNDocumentCameraViewControllerDelegate, CNContactPickerDelegate {
    private var webView: WKWebView!
    private var offlineView: UIView?
    private var downloads: [ObjectIdentifier: URL] = [:]
    private var openBook: BookItem?
    private var scanReply: ((Any?, String?) -> Void)?
    private var scanMulti = true
    private var contactReply: ((Any?, String?) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        // App-bound domains: lets the page keep itself on the device (service worker) so it opens offline.
        config.limitsNavigationsToAppBoundDomains = true
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true          // document scanner camera preview
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "Mobile/15E148 HalaqaApp"

        let content = config.userContentController
        content.addUserScript(WKUserScript(source: "window.HALAQA_NATIVE=true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addScriptMessageHandler(self, contentWorld: .page, name: "halaqaBio")
        content.addScriptMessageHandler(self, contentWorld: .page, name: "halaqaBook")
        content.addScriptMessageHandler(self, contentWorld: .page, name: "halaqaOCR")
        content.addScriptMessageHandler(self, contentWorld: .page, name: "halaqaContacts")
        if UIApplication.shared.supportsAlternateIcons {
            content.addScriptMessageHandler(self, contentWorld: .page, name: "halaqaIcon")
        }
        // Apple's document scanner (as in Notes and Files) for every camera button of the page
        if VNDocumentCameraViewController.isSupported {
            content.addUserScript(WKUserScript(source: "window.HALAQA_SCAN=true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            content.addScriptMessageHandler(self, contentWorld: .page, name: "halaqaScan")
        }

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
        NotificationCenter.default.addObserver(self, selector: #selector(pokePage), name: BookInbox.arrived, object: nil)
    }

    // MARK: - Face ID for the page (window.webkit.messageHandlers.halaqaBio)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        if message.name == "halaqaBook" { handleBook(message.body as? [String: Any] ?? [:], reply: replyHandler); return }
        if message.name == "halaqaOCR" { handleOCR(message.body as? [String: Any] ?? [:], reply: replyHandler); return }
        if message.name == "halaqaContacts" { pickContact(reply: replyHandler); return }
        if message.name == "halaqaIcon" { handleIcon(message.body as? [String: Any] ?? [:], reply: replyHandler); return }
        if message.name == "halaqaScan" { startScan(message.body as? [String: Any] ?? [:], reply: replyHandler); return }
        let action = (message.body as? [String: Any])?["action"] as? String ?? ""
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if action == "can" { replyHandler(available, nil); return }
        guard available else { replyHandler(false, nil); return }
        context.localizedCancelTitle = "استخدام الرمز السري"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "فتح تطبيق المدرسة القرءانية النموذجية") { ok, _ in
            DispatchQueue.main.async { replyHandler(ok, nil) }
        }
    }

    // MARK: - Home-screen icon (window.webkit.messageHandlers.halaqaIcon) — Apple allows changing the picture, not the name
    private let iconNames: Set<String> = ["AppIcon-Minarets", "AppIcon-Courtyard", "AppIcon-Gold"]

    private func handleIcon(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        let app = UIApplication.shared
        if (body["action"] as? String) != "set" { reply(app.alternateIconName ?? "AppIcon", nil); return }
        let wanted = body["name"] as? String ?? "AppIcon"
        let target: String? = iconNames.contains(wanted) ? wanted : nil
        if app.alternateIconName == target { reply(true, nil); return }
        app.setAlternateIconName(target) { error in
            DispatchQueue.main.async { reply(error == nil, nil) }
        }
    }

    // MARK: - Reading forms and documents (window.webkit.messageHandlers.halaqaOCR) — Apple's text recognition, on this device

    private func handleOCR(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard let s = body["img"] as? String, let data = Data(base64Encoded: s), let image = UIImage(data: data)?.cgImage else {
            reply(["text": "", "lines": [], "ar": false], nil); return
        }
        let digits = (body["mode"] as? String) == "digits"
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = !digits
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            var langs: [String] = []
            if !digits { langs += ["ar-SA", "ars-SA"].filter { supported.contains($0) } }
            langs += ["fr-FR", "en-US"].filter { supported.contains($0) }
            if !langs.isEmpty { request.recognitionLanguages = langs }
            var lines: [[String: Any]] = []
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            for obs in request.results ?? [] {
                guard let top = obs.topCandidates(1).first else { continue }
                let b = obs.boundingBox
                lines.append(["t": top.string, "c": Double(top.confidence), "x": Double(b.minX), "y": Double(1 - b.maxY), "w": Double(b.width), "h": Double(b.height)])
            }
            // reading order for Arabic pages: top to bottom, right to left
            lines.sort { a, b in
                let ay = a["y"] as? Double ?? 0, by = b["y"] as? Double ?? 0, ah = a["h"] as? Double ?? 0
                if abs(ay - by) > ah * 0.5 { return ay < by }
                return (a["x"] as? Double ?? 0) > (b["x"] as? Double ?? 0)
            }
            let text = lines.compactMap { $0["t"] as? String }.joined(separator: "\n")
            let arabic = langs.contains { $0.hasPrefix("ar") }
            DispatchQueue.main.async { reply(["text": text, "lines": lines, "ar": digits || arabic], nil) }
        }
    }

    // MARK: - Phone number from Contacts (window.webkit.messageHandlers.halaqaContacts)
    // Apple's own contacts picker: no permission needed, the app only gets the number the user taps.

    private func pickContact(reply: @escaping (Any?, String?) -> Void) {
        guard contactReply == nil else { reply("", nil); return }
        contactReply = reply
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.delegate = self
        top().present(picker, animated: true)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        let number = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
        let reply = contactReply
        contactReply = nil
        reply?(number, nil)
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        let reply = contactReply
        contactReply = nil
        reply?("", nil)
    }

    // MARK: - Apple's document scanner (window.webkit.messageHandlers.halaqaScan)
    // It finds the paper, cuts it out and straightens it; the pages go back to the page as JPEG (base64).

    private func startScan(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard scanReply == nil, VNDocumentCameraViewController.isSupported else { reply(["pages": [], "error": "busy"], nil); return }
        scanReply = reply
        scanMulti = (body["multi"] as? Bool) ?? true
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        scanner.modalPresentationStyle = .fullScreen
        top().present(scanner, animated: true)
    }

    private func finishScan(_ result: [String: Any]) {
        let reply = scanReply
        scanReply = nil
        reply?(result, nil)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        let count = scanMulti ? scan.pageCount : min(scan.pageCount, 1)
        let images = (0..<count).map { scan.imageOfPage(at: $0) }
        controller.dismiss(animated: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let pages: [[String: Any]] = images.compactMap { image in
                let small = WebViewController.fit(image, longest: 2400)
                guard let data = small.jpegData(compressionQuality: 0.86) else { return nil }
                return ["b": data.base64EncodedString(), "w": Int(small.size.width), "h": Int(small.size.height)]
            }
            DispatchQueue.main.async { self.finishScan(["pages": pages]) }
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        finishScan(["pages": []])
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        finishScan(["pages": [], "error": "camera"])
    }

    static func fit(_ image: UIImage, longest: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > longest else { return image }
        let scale = longest / side
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: - Links: the app stays inside, WhatsApp / phone / other sites open outside

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = (url.scheme ?? "").lowercased()
        if ["blob", "data", "about"].contains(scheme) { decisionHandler(.allow); return }
        // the students' follow-up page opens in Safari, not in place of the app
        if scheme == "https" && url.host == appHost && url.path.hasSuffix("talib.html") { UIApplication.shared.open(url); decisionHandler(.cancel); return }
        if scheme == "https" && url.host == appHost { decisionHandler(.allow); return }
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
        if let url = navigationAction.request.url {
            if url.host == appHost && !url.path.hasSuffix("talib.html") { webView.load(navigationAction.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    // MARK: - Saved files (backups, Excel, images) → share sheet

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

    // MARK: - Camera for the document scanner

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == appHost ? .grant : .deny)
    }

    // MARK: - alert / confirm / prompt from the page

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

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        top().present(alert, animated: true)
    }

    // MARK: - No internet on the very first launch

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let code = (error as NSError).code
        if code == NSURLErrorCancelled || code == 102 { return }
        if webView.url == nil || webView.url?.host != appHost || !webView.canGoBack { showOffline() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        offlineView?.removeFromSuperview()
        offlineView = nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - «الخزانة العلمية»: books shared in, and reading them with Quick Look

    private func handleBook(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        let id = body["id"] as? String ?? ""
        let title = body["title"] as? String ?? "كتاب"
        switch body["action"] as? String ?? "" {
        case "ready":
            reply(true, nil)
        case "pending":
            // books shared into the app and waiting for the page, plus copies left by an older version
            reply(["books": BookInbox.shared.pending(all: (body["all"] as? Bool) ?? false), "cached": BookCache.cachedIDs()], nil)
        case "read":
            reply(BookInbox.shared.piece(id, index: (body["i"] as? NSNumber)?.intValue ?? 0), nil)
        case "done":
            BookInbox.shared.finish(id)
            reply(true, nil)
        case "drop":
            // a page or a scanned PDF taken into «صندوق الوثائق»: the app's copy is no longer needed
            BookInbox.shared.drop(id)
            reply(true, nil)
        case "readCached":
            reply(BookInbox.piece(of: BookCache.url(for: id), index: (body["i"] as? NSNumber)?.intValue ?? 0), nil)
        case "open":
            let file = BookCache.url(for: id)
            if FileManager.default.fileExists(atPath: file.path) { showBook(file, title: title); reply("shown", nil) } else { reply("need", nil) }
        case "chunk":
            let part = BookCache.partURL(for: id)
            guard let s = body["s"] as? String, let data = Data(base64Encoded: s) else { reply(false, nil); return }
            if ((body["i"] as? NSNumber)?.intValue ?? 0) == 0 {
                reply(FileManager.default.createFile(atPath: part.path, contents: data), nil)
            } else if let handle = try? FileHandle(forWritingTo: part) {
                handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
                reply(true, nil)
            } else { reply(false, nil) }
        case "show":
            let file = BookCache.url(for: id), part = BookCache.partURL(for: id)
            try? FileManager.default.removeItem(at: file)
            guard (try? FileManager.default.moveItem(at: part, to: file)) != nil else { reply("failed", nil); return }
            showBook(file, title: title)
            reply("shown", nil)
        case "forget":
            try? FileManager.default.removeItem(at: BookCache.url(for: id))
            reply(true, nil)
        default:
            reply(nil, nil)
        }
    }

    private func showBook(_ file: URL, title: String) {
        openBook = BookItem(url: file, title: title)
        let preview = QLPreviewController()
        preview.dataSource = self
        preview.modalPresentationStyle = .fullScreen
        top().present(preview, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { openBook == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { openBook! }

    /// Tells the page that a book arrived; the page then asks for it piece by piece.
    @objc private func pokePage() {
        webView.evaluateJavaScript("window.halaqaBookPoll && halaqaBookPoll()", completionHandler: nil)
    }

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
        label.textColor = UIColor(red: 0.06, green: 0.12, blue: 0.2, alpha: 1)

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

// MARK: - Books shared from other apps («الخزانة العلمية»)

/// PDF files opened in this app from another app's share sheet wait in Caches/books/inbox until the page takes them.
/// Files iOS leaves in Documents/Inbox are picked up too, so nothing is lost if a hand-over is interrupted.
final class BookInbox {
    static let shared = BookInbox()
    static let arrived = Notification.Name("HalaqaBookArrived")
    static let step = 393_216   // a multiple of 3, so each piece is valid base64 on its own

    private let fm = FileManager.default
    private var folder: URL {
        let f = BookCache.folder.appendingPathComponent("inbox", isDirectory: true)
        try? fm.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }

    func receive(_ url: URL) {
        if take(url) { NotificationCenter.default.post(name: BookInbox.arrived, object: nil) }
    }

    @discardableResult private func take(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let id = "b" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 1296...46655), radix: 36)
        if url.pathExtension.lowercased() == "zip" {
            // a folder of books, compressed by iOS: the page opens the archive and takes out the PDFs
            do { try fm.copyItem(at: url, to: folder.appendingPathComponent(id + ".zip")) } catch { return false }
            try? url.lastPathComponent.write(to: folder.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
            if url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
            return true
        }
        if url.pathExtension.lowercased() != "pdf" {
            // a photo from a scanner app (JPEG, PNG, HEIC…): kept as JPEG, which the page can always open
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data),
                  let jpeg = WebViewController.fit(image, longest: 3000).jpegData(compressionQuality: 0.9),
                  (try? jpeg.write(to: folder.appendingPathComponent(id + ".jpg"))) != nil else { return false }
            try? url.lastPathComponent.write(to: folder.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
            if url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
            return true
        }
        let dest = folder.appendingPathComponent(id + ".pdf")
        do { try fm.copyItem(at: url, to: dest) } catch { return false }
        try? url.lastPathComponent.write(to: folder.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
        if url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
        return true
    }

    /// `all`: photos too (pages from 10.1 on); without it only PDFs, as older pages expect.
    func pending(all: Bool = false) -> [[String: Any]] {
        let systemInbox = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Inbox", isDirectory: true)
        for f in (try? fm.contentsOfDirectory(at: systemInbox, includingPropertiesForKeys: nil)) ?? [] where ["pdf", "zip", "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"].contains(f.pathExtension.lowercased()) {
            take(f)
        }
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        // a zip is a folder of books sent by the user; photos only reach pages that ask for them (all: true)
        return files.filter { $0.pathExtension == "pdf" || $0.pathExtension == "zip" || (all && $0.pathExtension == "jpg") }.map { f in
            let id = f.deletingPathExtension().lastPathComponent
            let kind = f.pathExtension
            let image = kind == "jpg"
            let name = (try? String(contentsOf: folder.appendingPathComponent(id + ".name"), encoding: .utf8)) ?? (image ? "صورة.jpg" : kind == "zip" ? "مجلد.zip" : "كتاب.pdf")
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return ["id": id, "name": name, "size": size, "type": image ? "image" : kind == "zip" ? "zip" : "pdf"]
        }
    }

    private func file(_ id: String) -> URL {
        let safe = BookCache.safe(id), jpg = folder.appendingPathComponent(safe + ".jpg"), zip = folder.appendingPathComponent(safe + ".zip")
        if fm.fileExists(atPath: jpg.path) { return jpg }
        if fm.fileExists(atPath: zip.path) { return zip }
        return folder.appendingPathComponent(safe + ".pdf")
    }

    func piece(_ id: String, index: Int) -> String {
        BookInbox.piece(of: file(id), index: index)
    }

    func drop(_ id: String) {
        let safe = BookCache.safe(id)
        for ext in ["jpg", "pdf", "zip", "name"] { try? fm.removeItem(at: folder.appendingPathComponent(safe + "." + ext)) }
    }

    /// Piece number `index` of a file as base64, or "" after the last piece.
    static func piece(of file: URL, index: Int) -> String {
        guard index >= 0, let h = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { h.closeFile() }
        h.seek(toFileOffset: UInt64(index) * UInt64(step))
        return h.readData(ofLength: step).base64EncodedString()
    }

    /// The page saved the book: keep the file as the quick-reading copy.
    func finish(_ id: String) {
        let safe = BookCache.safe(id)
        let src = folder.appendingPathComponent(safe + ".pdf"), dst = BookCache.url(for: safe)
        try? fm.removeItem(at: dst)
        if (try? fm.moveItem(at: src, to: dst)) == nil { try? fm.removeItem(at: src) }
        try? fm.removeItem(at: folder.appendingPathComponent(safe + ".name"))
    }
}

/// A copy of each book in Caches, so Quick Look can open it. The page keeps the real copy and resends it if iOS clears this folder.
enum BookCache {
    static var folder: URL {
        let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("books", isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }
    static func safe(_ id: String) -> String { String(id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40)) }
    static func url(for id: String) -> URL { folder.appendingPathComponent(safe(id) + ".pdf") }
    static func partURL(for id: String) -> URL { folder.appendingPathComponent(safe(id) + ".part") }
    static func cachedIDs() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "pdf" }.map { $0.deletingPathExtension().lastPathComponent }
    }
}

final class BookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL, title: String) { previewItemURL = url; previewItemTitle = title }
}
