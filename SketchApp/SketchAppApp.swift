//
//  SketchAppApp.swift
//  SketchApp
//
//  Created by Aaron on 26.06.26.
//

import SwiftUI
import PostHog
import Network

@main
struct SketchAppApp: App {
    init() {
        setupPostHogIfOnline()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .postHogScreenView("Drawing")
        }
    }

    private func setupPostHogIfOnline() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                DispatchQueue.main.async {
                    setupPostHog()
                }
            } else {
                print("[PostHog] device appears offline — skipping session replay setup")
            }
            monitor.cancel()
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }

    private func setupPostHog() {
        let config = PostHogConfig(
            projectToken: "<phc_pDF6HeaKAZkpo4YUxQFM2A7Fy7mHzTZoaVKiEeqFLv9t>",
            host: "https://eu.i.posthog.com"
        )

        // Session replay for the user study
        config.sessionReplay = true
        config.sessionReplayConfig.screenshotMode = true          // Required for SwiftUI
        config.sessionReplayConfig.maskAllTextInputs = true       // Default: mask text fields
        config.sessionReplayConfig.maskAllImages = true           // Default: mask images
        config.sessionReplayConfig.captureLogs = false            // Do not capture console logs
        config.sessionReplayConfig.captureNetworkTelemetry = true // Capture network timing/status only
        config.sessionReplayConfig.throttleDelay = 1.0            // Reduce capture frequency to save CPU

        PostHogSDK.shared.setup(config)
    }
}
