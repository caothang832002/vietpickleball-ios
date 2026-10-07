import UIKit
import WebKit
import SafariServices
import Network

/// Màn hình chính: mở VietPickleball.vn trong WKWebView, kèm các tiện ích của app:
/// kéo xuống để tải lại, thanh tiến trình, màn hình mất mạng (tự tải lại khi có mạng),
/// mở link ngoài bằng trình duyệt trong app, chia sẻ / lưu tệp tải về, quét mã bằng camera.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {

    static let home = URL(string: "https://vietpickleball.vn/")!
    static let ownHosts: Set<String> = ["vietpickleball.vn", "www.vietpickleball.vn"]
    static let brand = UIColor(red: 0x17 / 255.0, green: 0x10 / 255.0, blue: 0x2E / 255.0, alpha: 1)
    static let accent = UIColor(red: 0x8A / 255.0, green: 0x3B / 255.0, blue: 0xFF / 255.0, alpha: 1)

    private var webView: WKWebView!
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let offlineView = UIView()
    private let offlineTitle = UILabel()
    private var progressObserver: NSKeyValueObservation?
    private var pendingURL: URL?
    private var lastURL: URL = WebViewController.home
    private var downloadDestination: URL?
    private let pathMonitor = NWPathMonitor()
    private var isOnline = true

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Dựng giao diện

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.brand

        let config = WKWebViewConfiguration()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        config.applicationNameForUserAgent = "Mobile/15E148 VietPickleballApp/\(version)"
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        config.userContentController.add(self, name: "vpShare")
        config.userContentController.addUserScript(WKUserScript(source: Self.shareBridgeJS,
                                                                injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = Self.brand
        webView.scrollView.backgroundColor = Self.brand
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        let refresh = UIRefreshControl()
        refresh.tintColor = .white
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        progressBar.progressTintColor = Self.accent
        progressBar.trackTintColor = .clear
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressBar)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            progressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2.5)
        ])

        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
            guard let self = self else { return }
            let value = Float(web.estimatedProgress)
            self.progressBar.setProgress(value, animated: value > self.progressBar.progress)
            self.progressBar.isHidden = value >= 1
        }

        buildOfflineView()
        startNetworkMonitor()

        prepareLanguageCookie { [weak self] in
            guard let self = self else { return }
            self.load(self.pendingURL ?? self.startURL())
            self.pendingURL = nil
        }
    }

    /// Lần đầu mở app: chọn sẵn ngôn ngữ theo máy (tiếng Việt hoặc tiếng Anh) để trang không hỏi lại.
    private func prepareLanguageCookie(_ done: @escaping () -> Void) {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { cookies in
            if cookies.contains(where: { $0.name == "pb_lang" }) { done(); return }
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "vi"
            let lang = preferred.hasPrefix("vi") ? "vi" : "en"
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: "pb_lang", .value: lang, .domain: "vietpickleball.vn", .path: "/",
                .secure: "TRUE", .expires: Date().addingTimeInterval(365 * 24 * 3600)
            ]
            if let cookie = HTTPCookie(properties: props) {
                store.setCookie(cookie) { done() }
            } else {
                done()
            }
        }
    }

    private func startURL() -> URL {
        // Dùng khi chụp ảnh màn hình tự động: -startPath "?bxh=1"
        if let path = UserDefaults.standard.string(forKey: "startPath"), !path.isEmpty,
           let url = URL(string: path, relativeTo: Self.home)?.absoluteURL {
            return url
        }
        return Self.home
    }

    private func buildOfflineView() {
        offlineView.backgroundColor = Self.brand
        offlineView.isHidden = true
        offlineView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(offlineView)

        let logo = UIImageView(image: UIImage(named: "LaunchLogo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false

        offlineTitle.text = "Không kết nối được"
        offlineTitle.font = .systemFont(ofSize: 22, weight: .bold)
        offlineTitle.textColor = .white
        offlineTitle.textAlignment = .center
        offlineTitle.numberOfLines = 0

        let detail = UILabel()
        detail.text = "Kiểm tra Wi-Fi hoặc 4G rồi bấm Thử lại.\nApp sẽ tự tải lại khi có mạng."
        detail.font = .systemFont(ofSize: 16)
        detail.textColor = UIColor(white: 1, alpha: 0.75)
        detail.textAlignment = .center
        detail.numberOfLines = 0

        let retry = UIButton(type: .system)
        retry.setTitle("Thử lại", for: .normal)
        retry.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        retry.setTitleColor(.white, for: .normal)
        retry.backgroundColor = Self.accent
        retry.layer.cornerRadius = 12
        retry.contentEdgeInsets = UIEdgeInsets(top: 12, left: 36, bottom: 12, right: 36)
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [logo, offlineTitle, detail, retry])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(28, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        offlineView.addSubview(stack)

        NSLayoutConstraint.activate([
            offlineView.topAnchor.constraint(equalTo: view.topAnchor),
            offlineView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            offlineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            offlineView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logo.widthAnchor.constraint(equalToConstant: 96),
            logo.heightAnchor.constraint(equalToConstant: 96),
            stack.centerXAnchor.constraint(equalTo: offlineView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: offlineView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: offlineView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: offlineView.trailingAnchor, constant: -32)
        ])
    }

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let online = path.status == .satisfied
                let cameBack = online && !self.isOnline
                self.isOnline = online
                if cameBack && !self.offlineView.isHidden { self.load(self.lastURL) }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "vn.vietpickleball.net"))
    }

    // MARK: - Mở trang

    func load(_ url: URL) {
        guard isViewLoaded, webView != nil else { pendingURL = url; return }
        lastURL = url
        webView.load(URLRequest(url: url))
    }

    /// Link từ ngoài vào app: vietpickleball://?g=ten-giai hoặc https://vietpickleball.vn/...
    func open(link: URL) {
        if let host = link.host?.lowercased(), Self.ownHosts.contains(host), link.scheme?.hasPrefix("http") == true {
            load(link)
            return
        }
        if link.scheme?.lowercased() == "vietpickleball" {
            var target = "https://vietpickleball.vn/"
            if let query = link.query, !query.isEmpty { target += "?" + query }
            if let fragment = link.fragment, !fragment.isEmpty { target += "#" + fragment }
            if let url = URL(string: target) { load(url) }
        }
    }

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        if offlineView.isHidden && webView.url != nil {
            webView.reload()
        } else {
            load(lastURL)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { sender.endRefreshing() }
    }

    @objc private func retryTapped() {
        load(lastURL)
    }

    private func showOffline(_ show: Bool) {
        offlineView.isHidden = !show
        if show { webView.scrollView.refreshControl?.endRefreshing() }
    }

    private func isOwn(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Self.ownHosts.contains(host)
    }

    private func openOutside(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = Self.accent
            present(safari, animated: true)
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        let scheme = url.scheme?.lowercased() ?? ""
        switch scheme {
        case "about", "blob", "data", "javascript":
            decisionHandler(.allow)
        case "http", "https":
            if isOwn(url) || navigationAction.targetFrame?.isMainFrame == false {
                decisionHandler(.allow)
            } else {
                openOutside(url)
                decisionHandler(.cancel)
            }
        default:
            // tel:, mailto:, sms:, zalo:, app ngân hàng…
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download); return
        }
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().contains("attachment") {
            decisionHandler(.download); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url, isOwn(url) { lastURL = url }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showOffline(false)
        webView.scrollView.refreshControl?.endRefreshing()
        if let url = webView.url, isOwn(url) { lastURL = url }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        let ns = error as NSError
        webView.scrollView.refreshControl?.endRefreshing()
        // -999: bị hủy (bấm link khác); 102: chuyển sang tải tệp — không phải lỗi mạng
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 204) { return }
        if let failing = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL, isOwn(failing) { lastURL = failing }
        let offlineCodes: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                                      NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                                      NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff,
                                      NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed]
        offlineTitle.text = ns.code == NSURLErrorNotConnectedToInternet ? "Không có kết nối mạng" : "Không kết nối được"
        if ns.domain == NSURLErrorDomain && offlineCodes.contains(ns.code) { showOffline(true) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Link mở tab mới (target=_blank): trang của mình mở ngay trong app, trang ngoài mở trình duyệt.
        if let url = navigationAction.request.url {
            if isOwn(url) { webView.load(navigationAction.request) } else { openOutside(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentSafely(alert, orElse: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { _ in completionHandler(true) })
        presentSafely(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        presentSafely(alert) { completionHandler(nil) }
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Camera chỉ cho trang VietPickleball (chụp ảnh chân dung, quét mã vạch); iOS vẫn hỏi người dùng lần đầu.
        decisionHandler(Self.ownHosts.contains(origin.host.lowercased()) ? .grant : .deny)
    }

    private func presentSafely(_ controller: UIViewController, orElse fallback: @escaping () -> Void) {
        guard presentedViewController == nil, view.window != nil else { fallback(); return }
        present(controller, animated: true)
    }

    // MARK: - Tải tệp (PDF, Excel, ảnh…) -> bảng Chia sẻ / Lưu vào Tệp

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = suggestedFilename.isEmpty ? "vietpickleball" : suggestedFilename
        let destination = folder.appendingPathComponent(name)
        downloadDestination = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadDestination else { return }
        downloadDestination = nil
        share(items: [file])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestination = nil
        let alert = UIAlertController(title: "Không tải được tệp", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentSafely(alert) {}
    }

    private func share(items: [Any]) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        presentSafely(sheet) {}
    }

    // MARK: - Chia sẻ từ trang (navigator.share) -> bảng Chia sẻ của iOS

    /// Nếu WebView chưa có navigator.share thì thay bằng cầu nối gửi sang app (hỗ trợ cả ảnh, tệp).
    static let shareBridgeJS = """
    (function () {
      if (navigator.share && navigator.canShare) return;
      var toB64 = function (f) { return new Promise(function (ok, no) {
        var r = new FileReader(); r.onload = function () { ok({ name: f.name || 'tep', type: f.type || '', data: String(r.result).split(',')[1] || '' }); };
        r.onerror = no; r.readAsDataURL(f); }); };
      navigator.canShare = function () { return true; };
      navigator.share = function (d) {
        d = d || {};
        var files = Array.prototype.slice.call(d.files || []);
        return Promise.all(files.map(toB64)).then(function (fs) {
          window.webkit.messageHandlers.vpShare.postMessage({ title: d.title || '', text: d.text || '', url: d.url || '', files: fs });
        });
      };
    })();
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vpShare", let body = message.body as? [String: Any] else { return }
        var items: [Any] = []
        if let files = body["files"] as? [[String: Any]] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in files {
                guard let b64 = file["data"] as? String, let data = Data(base64Encoded: b64) else { continue }
                let rawName = (file["name"] as? String) ?? "tep"
                let name = rawName.replacingOccurrences(of: "/", with: "-")
                let url = folder.appendingPathComponent(name.isEmpty ? "tep" : name)
                if (try? data.write(to: url)) != nil { items.append(url) }
            }
        }
        let text = [body["title"] as? String, body["text"] as? String]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        if !text.isEmpty && items.isEmpty { items.append(text) }
        if let link = body["url"] as? String, let url = URL(string: link, relativeTo: webView.url)?.absoluteURL { items.append(url) }
        if !items.isEmpty { share(items: items) }
    }
}
