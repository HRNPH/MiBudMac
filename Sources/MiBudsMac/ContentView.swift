// SPDX-License-Identifier: MIT
// Copyright (c) 2026 HRNPH

import AppKit
import MiBudsCore
import SwiftUI

enum AppResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "MiBudsMac_MiBudsMac", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        return .module
    }()
    static let earbuds: NSImage? = bundle.url(forResource: "earbuds", withExtension: "png").flatMap
    { NSImage(contentsOf: $0) }
}

enum Palette {
    static let blue = Color(red: 0.19, green: 0.34, blue: 0.83)
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.23)
    static let muted = Color(red: 0.43, green: 0.47, blue: 0.54)
    static let canvas = Color(red: 0.965, green: 0.972, blue: 0.985)
    static let green = Color(red: 0.16, green: 0.53, blue: 0.39)
    static let line = Color(red: 0.87, green: 0.89, blue: 0.93)
}

private enum Page: String, CaseIterable {
    case overview = "My earbuds"
    case sound = "Sound"
    case touch = "Touch controls"
    case connection = "Connection"
    var symbol: String {
        switch self {
        case .overview: "earbuds"
        case .sound: "slider.horizontal.3"
        case .touch: "hand.tap"
        case .connection: "antenna.radiowaves.left.and.right"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: "Battery status and earbud settings."
        case .sound: "Equalizer presets and low latency."
        case .touch: "Configure actions for each earbud."
        case .connection: "Bluetooth connection and diagnostics."
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var buds: BudsController
    @State private var page = Page.overview
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if let error = buds.error { errorBanner(error) }
                    switch page {
                    case .overview:
                        hero
                        soundSection
                        latencySection
                    case .sound:
                        soundSection
                        latencySection
                        modelNote
                    case .touch: gestureSection
                    case .connection: connectionSection
                    }
                    footer
                }
                .padding(.horizontal, 38).padding(.top, 44).padding(.bottom, 28)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.canvas)
        }
        .frame(minWidth: 930, minHeight: 680)
        .foregroundStyle(Palette.ink).tint(Palette.blue)
        .preferredColorScheme(.light)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "earbuds").font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Palette.blue)
                Text("MiBuds").font(.system(size: 23, weight: .bold, design: .rounded)).tracking(
                    -0.7)
            }.padding(.top, 57).padding(.bottom, 42).padding(.leading, 26)
            VStack(spacing: 7) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button {
                        page = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).font(.system(size: 16)).frame(width: 21)
                            Text(item.rawValue).font(
                                .system(size: 13, weight: page == item ? .semibold : .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 15).padding(.vertical, 13)
                        .foregroundStyle(page == item ? Palette.blue : Palette.muted)
                        .background(
                            page == item ? Palette.blue.opacity(0.08) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 14)
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Circle().fill(buds.connected ? Palette.green : Palette.muted).frame(
                        width: 6, height: 6)
                    Text(buds.connected ? "Connected" : "Disconnected").font(.system(size: 11))
                }
                Text("Redmi Buds 6 Play").font(.system(size: 12, weight: .semibold))
                Button {
                    buds.openBluetoothSettings()
                } label: {
                    Label("Bluetooth Settings", systemImage: "arrow.up.right.square").font(
                        .system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
            }.padding(22)
            Divider().overlay(Palette.line).padding(.horizontal, 22)
            Text("Version 1.0.0").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(22)
        }
        .frame(width: 213).background(.white)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.line.opacity(0.6)).frame(width: 1)
        }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(page.rawValue).font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.9)
                Text(page.subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if buds.connecting || buds.busy {
                ProgressView().controlSize(.small).padding(.trailing, 8).accessibilityLabel(
                    buds.connecting ? "Connecting" : "Updating settings")
            }
            Button {
                if buds.connected { buds.refresh() } else { buds.connect() }
            } label: {
                Label(
                    buds.connected ? "Refresh" : buds.connecting ? "Connecting" : "Connect",
                    systemImage: buds.connected ? "arrow.clockwise" : "link"
                )
                .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 13).padding(
                    .vertical, 9)
            }
            .buttonStyle(.plain).background(.white, in: Capsule()).overlay(
                Capsule().stroke(Palette.line, lineWidth: 1)
            )
            .disabled(buds.busy || buds.connecting)
        }
    }
    private var hero: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) {
                        Circle().fill(buds.connected ? Palette.green : Palette.muted).frame(
                            width: 6, height: 6)
                        Text(buds.connected ? "Connected to your Mac" : buds.status).font(
                            .system(size: 11, weight: .medium)
                        ).foregroundStyle(Palette.muted)
                    }
                    Text("Redmi Buds\n6 Play").font(
                        .system(size: 36, weight: .semibold, design: .rounded)
                    ).tracking(-1.3).lineSpacing(-1).fixedSize(horizontal: true, vertical: true)
                    Text("Bluetooth earbud controls").font(.system(size: 13)).lineSpacing(4)
                        .foregroundStyle(Palette.muted)
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield")
                        Text(buds.connected ? "Settings available" : "Pair in Bluetooth Settings")
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.blue)
                        .padding(.top, 5)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().fill(Color(red: 0.90, green: 0.93, blue: 0.99)).frame(
                        width: 196, height: 196)
                    Circle().stroke(.white.opacity(0.7), lineWidth: 1).frame(
                        width: 225, height: 225)
                    if let image = AppResources.earbuds {
                        Image(nsImage: image).resizable().scaledToFit().frame(
                            width: 182, height: 226
                        )
                        .shadow(color: Palette.ink.opacity(0.12), radius: 14, x: 0, y: 15)
                    }
                }.frame(width: 240, height: 244).accessibilityLabel(
                    "Redmi Buds 6 Play in their charging case")
            }
            Divider().overlay(Palette.line.opacity(0.5))
            HStack(spacing: 30) {
                ForEach(0..<3) { index in batteryRow(index).frame(maxWidth: .infinity) }
            }.padding(.horizontal, 6).padding(.bottom, 3)
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line.opacity(0.6), lineWidth: 1))
    }
    private func batteryRow(_ index: Int) -> some View {
        let battery = buds.batteries.indices.contains(index) ? buds.batteries[index] : nil
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: index == 2 ? "case" : "earbuds").font(.system(size: 11))
                Text(["Left earbud", "Right earbud", "Case"][index]).font(.system(size: 10))
            }.foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(battery?.percent.map(String.init) ?? "N/A").font(
                    .system(size: 25, weight: .semibold, design: .rounded)
                ).monospacedDigit()
                if battery?.percent != nil {
                    Text("%").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if battery?.charging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(
                        Palette.green)
                }
            }
            GeometryReader { geo in
                Capsule().fill(Palette.line.opacity(0.5)).overlay(alignment: .leading) {
                    Capsule().fill((battery?.percent ?? 100) <= 20 ? Color.orange : Palette.green)
                        .frame(width: geo.size.width * Double(battery?.percent ?? 0) / 100)
                }
            }.frame(height: 3)
        }.padding(.vertical, 7)
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 18, weight: .semibold, design: .rounded)).tracking(
                    -0.3)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
    }
    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                "Equalizer",
                subtitle: buds.profile == nil
                    ? "Connect and refresh to read your sound profile."
                    : "Select a preset to save it on the earbuds.")
            HStack(spacing: 10) {
                ForEach(BudsCodec.profiles, id: \.id) { item in
                    let selected = buds.profile == item.id
                    Button {
                        buds.setProfile(item.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: item.symbol).font(
                                    .system(size: 19, weight: .medium))
                                Spacer(minLength: 0)
                                if selected {
                                    Image(systemName: "checkmark.circle.fill").font(
                                        .system(size: 12))
                                }
                            }
                            Text(item.name).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(selected ? .white : Palette.ink)
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading).frame(
                            height: 95
                        )
                        .background(
                            selected ? Palette.blue : .white, in: RoundedRectangle(cornerRadius: 13)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13).stroke(
                                selected ? .clear : Palette.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain).disabled(
                        !buds.connected || buds.busy || buds.profile == nil
                    )
                    .help(item.detail).accessibilityLabel(
                        "\(item.name): \(item.detail)\(selected ? ", selected" : "")")
                }
            }
        }
    }
    private var latencySection: some View {
        HStack(spacing: 16) {
            Image(systemName: "bolt.horizontal").font(.system(size: 22)).foregroundStyle(
                Palette.blue
            ).frame(width: 43, height: 43).background(
                Palette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text("Low latency").font(.system(size: 13, weight: .semibold))
                Text(
                    buds.lowLatency == nil
                        ? "Waiting for the earbuds’ current setting."
                        : "Reduce audio delay for games and videos."
                ).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if buds.lowLatency == nil {
                Text("Unread").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Toggle(
                "Low latency",
                isOn: Binding(get: { buds.lowLatency ?? false }, set: buds.setLatency)
            )
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .disabled(!buds.connected || buds.busy || buds.lowLatency == nil)
        }
        .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line.opacity(0.6), lineWidth: 1))
    }
    private var modelNote: some View {
        Label(
            "Low latency may reset when you close the charging case. Sound presets and gestures are saved on your earbuds.",
            systemImage: "info.circle"
        )
        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5)
    }
    private var gestureSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle(
                "Gesture assignments",
                subtitle: "Changes are saved to your earbuds and checked with a fresh read.")
            HStack {
                Text("Gesture")
                Spacer()
                Text("Left earbud").frame(width: 170)
                Text("Right earbud").frame(width: 170)
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).padding(
                .horizontal, 20)
            VStack(spacing: 0) {
                ForEach(BudsCodec.gestureNames, id: \.id) { item in
                    HStack(spacing: 16) {
                        Image(systemName: item.id == 3 ? "hand.point.up" : "hand.tap").font(
                            .system(size: 20)
                        ).foregroundStyle(Palette.blue).frame(width: 30)
                        Text(item.name).font(.system(size: 13, weight: .medium))
                        Spacer()
                        ForEach(0..<2) { side in
                            Picker(
                                "\(item.name), \(side == 0 ? "left" : "right") earbud",
                                selection: Binding<UInt8>(
                                    get: { buds.gestures[item.id]?[side] ?? 255 },
                                    set: { buds.setGesture(item.id, side: side, action: $0) }
                                )
                            ) {
                                Text("Not read").tag(UInt8(255))
                                if let current = buds.gestures[item.id]?[side], current != 255,
                                    !BudsCodec.allowedActions(item.id).contains(current)
                                {
                                    Text("Device action \(current)").tag(current)
                                }
                                ForEach(BudsCodec.allowedActions(item.id), id: \.self) { action in
                                    Text(BudsCodec.actions[action] ?? "Action \(action)").tag(
                                        action)
                                }
                            }.labelsHidden().frame(width: 170).disabled(
                                !buds.connected || buds.busy || buds.gestures[item.id] == nil)
                        }
                    }.padding(20)
                    if item.id != 3 { Divider().padding(.horizontal, 20) }
                }
            }.background(.white, in: RoundedRectangle(cornerRadius: 17))
            Label(
                "Available actions follow the Redmi Buds 6 Play device catalog. Some actions depend on the connected device.",
                systemImage: "info.circle"
            ).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "earbuds").font(.largeTitle).foregroundStyle(Palette.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Redmi Buds 6 Play").font(.headline)
                        Text(buds.status).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button(buds.connected || buds.connecting ? "Disconnect controls" : "Connect") {
                        if buds.connected || buds.connecting {
                            buds.autoConnect = false
                            buds.disconnect()
                        } else {
                            buds.connect()
                        }
                    }.buttonStyle(.bordered)
                }
                Divider()
                Toggle("Reconnect automatically", isOn: $buds.autoConnect).toggleStyle(.switch)
                    .controlSize(.small)
                Text(
                    "Pair your earbuds in macOS Bluetooth Settings first. If controls time out, close Xiaomi Earbuds or other companion apps on nearby devices, then reconnect."
                ).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5)
                Button("Open Bluetooth Settings") { buds.openBluetoothSettings() }.buttonStyle(
                    .borderedProminent)
            }.padding(24).background(.white, in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Connection details").font(.headline)
                    Spacer()
                    Button(copied ? "Copied" : "Copy diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            buds.log.joined(separator: "\n"), forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }.buttonStyle(.bordered)
                }
                Text(buds.transport).font(.system(size: 12)).foregroundStyle(Palette.muted)
                ScrollView {
                    Text(
                        buds.log.isEmpty
                            ? "Connection events will appear here."
                            : buds.log.joined(separator: "\n")
                    ).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(
                        maxWidth: .infinity, alignment: .leading)
                }.frame(height: 150)
            }.padding(24).background(.white, in: RoundedRectangle(cornerRadius: 17))
            HStack {
                Text("MiBudsClient protocol. GPLv3. No warranty.").font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Link(
                    "Protocol source",
                    destination: URL(string: "https://github.com/CesurPolat/MiBudsClient")!)
            }.font(.system(size: 11))
        }
    }
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Palette.blue)
            Text(message).font(.system(size: 12)).lineSpacing(4).frame(
                maxWidth: .infinity, alignment: .leading)
            Button {
                buds.error = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
        }.padding(15).background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle").foregroundStyle(Palette.green)
            Text(
                buds.lastUpdate.map {
                    "Battery updated \($0.formatted(date: .omitted, time: .shortened))"
                } ?? "Battery levels appear when the earbuds report them.")
            Spacer()
            Text("MiBuds for Mac").foregroundStyle(Palette.muted.opacity(0.7))
        }.font(.system(size: 10)).foregroundStyle(Palette.muted)
    }
}
