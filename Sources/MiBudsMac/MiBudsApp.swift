// SPDX-License-Identifier: MIT
// Copyright (c) 2026 HRNPH

import AppKit
import SwiftUI

@main
struct MiBudsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var buds = BudsController()

    var body: some Scene {
        Window("MiBuds", id: "main") {
            ContentView().environmentObject(buds)
                .task {
                    delegate.controller = buds
                    buds.start()
                }
        }
        .defaultSize(width: 1100, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MiBuds") { showAbout() }
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh earbuds") { buds.refresh() }.keyboardShortcut("r").disabled(
                    !buds.connected || buds.busy)
                Button("Bluetooth Settings…") { buds.openBluetoothSettings() }
            }
        }
        MenuBarExtra("MiBuds", systemImage: "earbuds") {
            MenuContent().environmentObject(buds)
        }
        .menuBarExtraStyle(.window)
    }
    private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "MiBuds for Mac", .applicationVersion: "1.0.0",
            .credits: NSAttributedString(
                string:
                    "Native Swift companion for Redmi Buds 6 Play.\nProtocol and earbud image adapted from CesurPolat/MiBudsClient.\nApp: GPLv3. Original interface: MIT. No warranty.\nSee the included license files and credits.\nIndependent project; not affiliated with Xiaomi."
            ),
        ])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: BudsController?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { controller?.disconnect() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchServices normally reuses the app; guard direct launches as well.
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.mibuds.mac"
        )
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate()
            NSApp.terminate(nil)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var buds: BudsController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "earbuds").foregroundStyle(Palette.blue)
                Text("MiBuds").font(.headline)
                Spacer()
                Circle().fill(buds.connected ? Palette.green : .gray).frame(width: 7, height: 7)
            }
            Text("Redmi Buds 6 Play").font(.title3.weight(.semibold))
            if buds.batteries.count == 3 {
                HStack {
                    ForEach(0..<3) { i in
                        VStack(spacing: 5) {
                            Text(["Left", "Right", "Case"][i]).foregroundStyle(.secondary)
                            Text(buds.batteries[i].percent.map { "\($0)%" } ?? "N/A").font(
                                .headline)
                        }.frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text(buds.status).foregroundStyle(.secondary)
            }
            Divider()
            if buds.connected {
                Toggle(
                    "Low latency",
                    isOn: Binding(get: { buds.lowLatency ?? false }, set: buds.setLatency)
                )
                .disabled(buds.busy || buds.lowLatency == nil)
                Button("Refresh") { buds.refresh() }.disabled(buds.busy)
            } else {
                Button(buds.connecting ? "Connecting…" : "Connect earbuds") { buds.connect() }
                    .disabled(buds.connecting)
            }
            if let error = buds.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            Button("Open MiBuds") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit MiBuds") { NSApp.terminate(nil) }.foregroundStyle(.secondary)
        }
        .padding(22).frame(width: 280).tint(Palette.blue)
    }
}
