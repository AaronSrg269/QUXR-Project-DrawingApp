import SwiftUI
import WebKit

struct ModelDisplayView: View {
    let glbData: Data?
    let isLoading: Bool

    var body: some View {
        ZStack {
            Theme.background
            ModelWebContainer(glbData: glbData)
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.accent)
            } else if glbData == nil {
                VStack(spacing: 8) {
                    Image(systemName: "rotate.3d")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.accent.opacity(0.5))
                    Text("Generated model will appear here")
                        .foregroundColor(Theme.textPrimary.opacity(0.45))
                        .font(.subheadline)
                }
            }
        }
    }
}

struct ModelWebContainer: UIViewRepresentable {
    let glbData: Data?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor(Theme.background)
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let data = glbData else {
            context.coordinator.reset(in: webView)
            return
        }
        context.coordinator.load(data: data, into: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var currentData: Data?

        @MainActor func reset(in webView: WKWebView) {
            currentData = nil
            webView.loadHTMLString(blankHTML, baseURL: nil)
        }

        @MainActor func load(data: Data, into webView: WKWebView) {
            guard currentData != data else { return }
            currentData = data

            let baseDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("model_viewer", isDirectory: true)
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            let glbURL = baseDir.appendingPathComponent("model.glb")
            let htmlURL = baseDir.appendingPathComponent("index.html")

            do {
                try data.write(to: glbURL, options: [.atomic])
                try viewerHTML.write(to: htmlURL, atomically: true, encoding: .utf8)
                webView.loadFileURL(htmlURL, allowingReadAccessTo: baseDir)
            } catch {
                print("[ModelWeb] error writing model files: \(error)")
            }
        }
    }
}

private let viewerHTML = """
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <script type="module" src="https://ajax.googleapis.com/ajax/libs/model-viewer/3.5.0/model-viewer.min.js"></script>
    <style>
        body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: #0D0F1A; }
        model-viewer { width: 100%; height: 100%; --poster-color: transparent; }
    </style>
</head>
<body>
    <model-viewer src="model.glb" camera-controls auto-rotate shadow-intensity="1" exposure="1"></model-viewer>
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
