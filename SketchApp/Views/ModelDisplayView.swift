import SwiftUI
import WebKit

struct ModelDisplayView: View {
    let glbData: Data?
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background
            ModelWebContainer(glbData: glbData)
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Theme.accent)
                    Text("Please allow for up to 20 seconds\nfor the 3D model to generate")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Theme.textPrimary.opacity(0.55))
                }
                .padding(.bottom, 24)
            } else if glbData == nil {
                VStack(spacing: 8) {
                    Image(systemName: "rotate.3d")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.accent.opacity(0.5))
                    Text("Generated model will appear here")
                        .foregroundColor(Theme.textPrimary.opacity(0.45))
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ModelWebContainer: UIViewRepresentable {
    let glbData: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "debug")
        config.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "modelviewer")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor(Theme.background)
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let data = glbData else {
            context.coordinator.reset(in: webView)
            return
        }
        context.coordinator.load(data: data, into: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let schemeHandler = ModelViewerSchemeHandler()
        private var currentData: Data?

        @MainActor func reset(in webView: WKWebView) {
            currentData = nil
            schemeHandler.glbData = Data()
            webView.loadHTMLString(blankHTML, baseURL: nil)
        }

        @MainActor func load(data: Data, into webView: WKWebView) {
            guard currentData != data else { return }
            currentData = data
            print("[ModelWeb] loading GLB, \(data.count) bytes, header: \(data.prefix(8).map { String(format: "%02x", $0) }.joined())")

            guard let jsURL = Bundle.main.url(forResource: "model-viewer-umd", withExtension: "js"),
                  let jsData = try? Data(contentsOf: jsURL) else {
                print("[ModelWeb] bundled model-viewer UMD JS not found")
                return
            }

            schemeHandler.htmlData = viewerHTML.data(using: .utf8) ?? Data()
            schemeHandler.jsData = jsData
            schemeHandler.glbData = data

            webView.load(URLRequest(url: URL(string: "modelviewer://localhost/index.html")!))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[ModelWeb] HTML finished loading")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[ModelWeb] navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[ModelWeb] provisional navigation failed: \(error)")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            print("[ModelWeb JS] \(message.body)")
        }
    }
}

final class ModelViewerSchemeHandler: NSObject, WKURLSchemeHandler {
    var htmlData = Data()
    var jsData = Data()
    var glbData = Data()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "ModelViewer", code: -1))
            return
        }
        let path = url.path
        switch path {
        case "/index.html":
            respond(urlSchemeTask, data: htmlData, mimeType: "text/html")
        case "/model-viewer-umd.js":
            respond(urlSchemeTask, data: jsData, mimeType: "application/javascript")
        case "/model.glb":
            respond(urlSchemeTask, data: glbData, mimeType: "model/gltf-binary")
        default:
            urlSchemeTask.didFailWithError(NSError(domain: "ModelViewer", code: 404))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // no-op
    }

    private func respond(_ task: WKURLSchemeTask, data: Data, mimeType: String) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType,
                    "Content-Length": String(data.count),
                    "Access-Control-Allow-Origin": "*"
                ]
              ) else {
            task.didFailWithError(NSError(domain: "ModelViewer", code: -1))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}

private let viewerHTML = """
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <script src="model-viewer-umd.js"></script>
    <script>
        function log(msg) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.debug) {
                window.webkit.messageHandlers.debug.postMessage(msg);
            }
        }
        window.addEventListener('error', function(e) {
            log('JS ERROR: ' + e.message + ' at ' + e.filename + ':' + e.lineno);
        });
        window.addEventListener('load', function() {
            log('window load');
            const mv = document.querySelector('model-viewer');
            if (!mv) { log('model-viewer element NOT found'); return; }
            log('model-viewer element found, defined=' + (window.customElements.get('model-viewer') ? 'yes' : 'no'));
            if (window.customElements.get('model-viewer')) {
                attachModelViewerListeners(mv);
            } else {
                customElements.whenDefined('model-viewer').then(() => {
                    log('model-viewer custom element defined');
                    attachModelViewerListeners(document.querySelector('model-viewer'));
                });
            }
            setTimeout(() => {
                log('status check after 5s: loaded=' + mv.loaded + ' src=' + mv.getAttribute('src'));
            }, 5000);
        });
        function attachModelViewerListeners(mv) {
            log('attaching model-viewer listeners');
            mv.addEventListener('load', function() {
                log('model-viewer: model loaded');
                mv.classList.add('loaded');
            });
            mv.addEventListener('error', function(e) {
                log('model-viewer error type=' + (e.detail && e.detail.type));
                log('model-viewer error message=' + (e.detail && e.detail.sourceError && e.detail.sourceError.message));
                log('model-viewer error string=' + (e.detail && e.detail.sourceError && e.detail.sourceError.toString()));
                log('model-viewer error detail=' + JSON.stringify(e.detail));
            });
            mv.addEventListener('preload', function() { log('model-viewer: preloading'); });
            mv.addEventListener('model-visibility', function() { log('model-viewer: model visibility changed'); });
        }
    </script>
    <style>
        body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: #0D0F1A; }
        model-viewer { width: 100%; height: 100%; --poster-color: #1a1c29; opacity: 0; transition: opacity 0.6s ease-in; will-change: opacity; transform: translateZ(0); }
        model-viewer.loaded { opacity: 1; }
    </style>
</head>
<body>
    <model-viewer src="model.glb" auto-rotate auto-rotate-delay="0" rotation-per-second="27deg" shadow-intensity="1" exposure="1" alt="Generated 3D model">
    </model-viewer>
</body>
</html>
"""

private let blankHTML = """
<!DOCTYPE html>
<html>
<body style="margin:0; padding:0; background-color:#0D0F1A;">
</body>
</html>
"""
