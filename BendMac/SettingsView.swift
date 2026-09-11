import MetalKit
import SwiftUI

struct MetalPreview: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> MTKView {
        let view = context.coordinator.renderer?.makeView() ?? MTKView()
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        view.setNeedsDisplay(view.bounds)
    }
    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor final class Coordinator {
        let renderer: BendRenderer?
        init(model: AppModel) {
            renderer = try? BendRenderer(frames: model.previewFrames)
            renderer?.parameters = { [weak model] in
                model?.parameters(preview: true) ?? BendParameters()
            }
        }
    }
}

private enum SettingsPage: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case lid = "Lid Behavior"
    case about = "About"

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "square.on.square"
        case .lid: "macbook"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var sidebarSelection
    @State private var page = SettingsPage.appearance
    @State private var history: [SettingsPage] = []
    @State private var forwardHistory: [SettingsPage] = []
    @State private var coffeeHovered = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch page {
                        case .general: general
                        case .appearance: appearance
                        case .lid: lidBehavior
                        case .about: about
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .id(page)
                .transition(
                    reduceMotion
                        ? .identity
                        : .modifier(
                            active: PageTransition(amount: 1), identity: PageTransition(amount: 0)))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: page)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 740, idealWidth: 800, minHeight: 670, idealHeight: 720)
        .onDisappear { model.previewPlaying = false }
        .ignoresSafeArea(.container, edges: .top)
        .tint(.blue)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsPage.allCases, id: \.self) { item in
                Button {
                    navigate(to: item)
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 13, weight: page == item ? .medium : .regular))
                        .labelStyle(SidebarLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .foregroundStyle(page == item ? Color.white : Color.primary)
                        .background {
                            if page == item {
                                selectionBackground
                                    .matchedGeometryEffect(id: "sidebar-selection", in: sidebarSelection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Text("BendMac \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 12)
            Spacer()
            Link(destination: URL(string: "https://buymeacoffee.com/jamiepen")!) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Buy me a coffee")
                            .font(.system(size: 11, weight: .medium))
                        Text("Optional. Always free.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(.orange)
                        .offset(y: coffeeHovered && !reduceMotion ? -1 : 0)
                }
                .labelStyle(SidebarLabelStyle())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 46)
                .background(
                    Color.orange.opacity(coffeeHovered ? 0.14 : 0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.orange.opacity(coffeeHovered ? 0.25 : 0.12))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { coffeeHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: coffeeHovered)
            .help(
                "Support Jamie’s student project. Opens Buy Me a Coffee in your browser. BendMac stays completely free."
            )
            .padding(.bottom, 8)
            Button(action: updates.checkForUpdates) {
                Label(
                    updates.availableVersion == nil ? "Check for updates" : "Update available",
                    systemImage: "arrow.down.circle"
                )
                .font(.system(size: 11, weight: .medium))
                .labelStyle(SidebarLabelStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(
                    updates.availableVersion == nil ? Color.clear : Color.blue.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(updates.availableVersion == nil ? Color.secondary : Color.blue)
            .disabled(!updates.canCheckForUpdates)
            .help(
                updates.availableVersion.map { "Version \($0) is available. Click to download and install." }
                    ?? "Checks automatically at launch and every six hours while running.")
            HStack(spacing: 9) {
                Circle().fill(model.enabled ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)
                    .frame(width: 15)
                Text(
                    model.enabled
                        ? "Effect enabled"
                        : model.starting
                            ? "Connecting…" : model.wantsEnabled ? "Needs attention" : "Effect paused"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 36)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: page)
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .padding(.bottom, 12)
        .frame(width: 176)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                SidebarBackdrop()
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.07), .clear, .white.opacity(0.015)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .allowsHitTesting(false)
                    }
            }
        }
    }

    private var selectionBackground: some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                SidebarSelectionGlass()
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor)
            }
        }
        .allowsHitTesting(false)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left").frame(width: 22, height: 24)
            }
            .disabled(history.isEmpty)
            .help("Back")
            .accessibilityLabel("Previous settings page")
            Button {
                goForward()
            } label: {
                Image(systemName: "chevron.right").frame(width: 22, height: 24)
            }
            .disabled(forwardHistory.isEmpty)
            .help("Forward")
            .accessibilityLabel("Next settings page")
            Text(page.rawValue).font(.system(size: 13, weight: .semibold)).padding(.leading, 6)
            Spacer()
            Toggle(
                isOn: Binding(
                    get: { model.wantsEnabled },
                    set: { if $0 { model.enable() } else { model.disable() } }
                )
            ) {
                Text(
                    model.starting
                        ? "Connecting…"
                        : model.enabled
                            ? "Enabled" : model.wantsEnabled ? "Needs attention" : "Enable BendMac"
                )
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .accessibilityLabel("Enable BendMac")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private func navigate(to next: SettingsPage) {
        guard page != next else { return }
        history.append(page)
        forwardHistory.removeAll()
        page = next
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        forwardHistory.append(page)
        page = previous
    }

    private func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        history.append(page)
        page = next
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 16) {
                VStack(spacing: 5) {
                    Text("A little flexibility.")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Your desktop, in step with your lid.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        MetalPreview(model: model)
                            .aspectRatio(1.6, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(7)
                            .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 14))
                        UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                            .fill(Color(white: 0.07))
                            .frame(width: 48, height: 10)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 22)
                    ZStack(alignment: .top) {
                        UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.8), Color(white: 0.54)], startPoint: .top,
                                    endPoint: .bottom)
                            )
                            .frame(height: 9)
                        UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                            .fill(Color(white: 0.42)).frame(width: 48, height: 3)
                    }
                }
                .frame(maxWidth: 310)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 7)
                .accessibilityLabel("Animated desktop preview")
                HStack(spacing: 12) {
                    Button {
                        if model.previewPlaying { model.previewPlaying = false } else { model.playPreview() }
                    } label: {
                        Image(systemName: model.previewPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 14, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(model.previewPlaying ? "Pause preview" : "Play fold preview")
                    .accessibilityLabel(model.previewPlaying ? "Pause fold preview" : "Play fold preview")
                    Slider(
                        value: $model.previewAngle, in: 12...135,
                        onEditingChanged: { _ in
                            model.previewPlaying = false
                        }
                    )
                    .disabled(model.previewFollowsLid)
                    .accessibilityLabel("Preview lid angle")
                    Text("\(Int(model.displayedPreviewAngle))°")
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .frame(maxWidth: 290)
                Toggle("Use live lid angle", isOn: $model.previewFollowsLid)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .disabled(model.sensorAngle == nil)
                    .onChange(of: model.previewFollowsLid) { _, follows in
                        if follows { model.previewPlaying = false }
                    }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            SettingsSection("Appearance") {
                VStack(spacing: 0) {
                    HStack {
                        Text("Style")
                        Spacer()
                        Picker("Style", selection: $model.style) {
                            Text("Silk").tag(0)
                            Text("Shade").tag(1)
                            Text("Frost").tag(2)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 240)
                    }
                    .padding(14)
                    rowDivider
                    sliderRow(
                        "Perspective", detail: "How far the upper edges draw inward.",
                        value: $model.perspective)
                    rowDivider
                    sliderRow("Blur", detail: "Softens the desktop toward the top.", value: $model.blur)
                    rowDivider
                    sliderRow("Shadow", detail: "Adds depth along the folded edges.", value: $model.shadow)
                }
            }
            Button {
                model.resetAppearance()
            } label: {
                Label("Reset appearance", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Desktop effect") {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(
                        isOn: Binding(
                            get: { model.wantsEnabled },
                            set: { enabled in
                                if enabled { model.enable() } else { model.disable() }
                            })
                    ) {
                        SettingCaption(
                            title: model.starting ? "Connecting…" : "Enable BendMac",
                            detail: "Let your desktop follow the lid.")
                    }
                    .toggleStyle(.switch).controlSize(.small).padding(14)
                    rowDivider
                    Toggle(isOn: Binding(get: { model.openAtLogin }, set: model.setOpenAtLogin)) {
                        SettingCaption(
                            title: "Open at login",
                            detail: "Start in the menu bar and restore the effect if it was on.")
                    }
                    .toggleStyle(.switch).controlSize(.small).padding(14)
                    rowDivider
                    Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                        .textSelection(.enabled).padding(14)
                }
            }
            if model.wantsEnabled && !model.enabled && !model.starting {
                Button("Try connecting again", action: model.enable)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            SettingsSection("Screen Recording") {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Your desktop stays on your Mac", systemImage: "lock.shield")
                        .font(.system(size: 13, weight: .medium))
                    Text(
                        "BendMac needs Screen Recording permission to apply the effect to your desktop. Frames stay in memory. No audio, saved recordings, or uploads."
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
                        horizontal: false, vertical: true)
                    Button("Open Screen Recording settings…") {
                        NSWorkspace.shared.open(
                            URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                            )!)
                    }
                    .controlSize(.small)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsSection("Using BendMac") {
                VStack(spacing: 0) {
                    informationRow(
                        "Pause instantly", detail: "Press Escape while the effect is visible.",
                        symbol: "escape")
                    rowDivider
                    informationRow(
                        "Always close by", detail: "Closing this window leaves BendMac in the menu bar.",
                        symbol: "menubar.rectangle")
                    rowDivider
                    informationRow(
                        "Built-in display only", detail: "The effect pauses for sleep and display changes.",
                        symbol: "display")
                }
            }
        }
    }

    private var lidBehavior: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Lid sensor") {
                VStack(spacing: 0) {
                    HStack {
                        SettingCaption(
                            title: model.sensorAngle == nil ? "Sensor unavailable" : "Sensor connected",
                            detail: "The current angle of your MacBook lid.")
                        Spacer()
                        Text(model.sensorAngle.map { "\(Int($0))°" } ?? "—")
                            .font(.system(size: 24, weight: .light)).monospacedDigit()
                    }.padding(16)
                    rowDivider
                    Toggle(isOn: $model.followLid) {
                        SettingCaption(
                            title: "Follow physical lid",
                            detail: "Turn off to set the desktop angle manually.")
                    }.toggleStyle(.switch).controlSize(.small).padding(14)
                    if !model.followLid {
                        rowDivider
                        sliderRow(
                            "Desktop angle", detail: "Controls the live effect when enabled.",
                            value: $model.manualAngle, range: 12...135, degrees: true)
                    }
                }
            }
            SettingsSection("Motion & sound") {
                VStack(spacing: 0) {
                    sliderRow(
                        "Clear at", detail: "The desktop returns to normal above this angle.",
                        value: $model.clearAngle, range: 80...135, degrees: true)
                    HStack {
                        Text("Use your comfortable viewing position.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Use current angle", action: model.calibrateOpenAngle)
                            .controlSize(.small)
                            .disabled(model.sensorAngle == nil)
                            .help("Sets the clear angle to your current lid angle, between 80° and 135°.")
                    }.padding(.horizontal, 14).padding(.bottom, 14)
                    rowDivider
                    Toggle(isOn: $model.sound) {
                        SettingCaption(
                            title: "Play a soft sound", detail: "When the desktop finishes unfolding.")
                    }.toggleStyle(.switch).controlSize(.small).padding(14)
                }
            }
            Text(
                "Lid sensor support varies by MacBook model and macOS version. You can always try the preview in Appearance."
            )
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 76, height: 76)
                Text("BendMac").font(.system(size: 23, weight: .semibold))
                Text("A little flexibility for your desktop.").font(.system(size: 12)).foregroundStyle(
                    .secondary)
            }.padding(.vertical, 18)
            SettingsSection("Updates") {
                HStack {
                    SettingCaption(
                        title: updates.availableVersion.map { "Version \($0) is available" }
                            ?? "Keep BendMac up to date",
                        detail: "Download and install updates without leaving the app.")
                    Spacer()
                    Button(
                        updates.availableVersion == nil ? "Check for updates…" : "View update…",
                        action: updates.checkForUpdates
                    )
                    .controlSize(.small)
                    .disabled(!updates.canCheckForUpdates)
                }.padding(16)
            }
            SettingsSection("Free & open source") {
                VStack(alignment: .leading, spacing: 16) {
                    Text(
                        "BendMac is free to use and released under the MIT license. Bug reports, ideas, and contributions are welcome."
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Link("Website ↗", destination: URL(string: "https://bendmac.app")!)
                        Spacer()
                        Link("GitHub ↗", destination: URL(string: "https://github.com/IuCC123/BendMac")!)
                    }.font(.system(size: 12))
                }.padding(16)
            }
            SettingsSection("Inspiration") {
                VStack(alignment: .leading, spacing: 10) {
                    Link("Inspired by Bendy ↗", destination: URL(string: "https://trybendy.app")!)
                        .font(.system(size: 13, weight: .medium))
                    Text(
                        "An independent implementation of the folding-desktop idea. Not affiliated with Bendy or Apple."
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rowDivider: some View { Divider().padding(.horizontal, 14).opacity(0.5) }

    private func sliderRow(
        _ title: String, detail: String, value: Binding<Double>, range: ClosedRange<Double> = 0...1,
        degrees: Bool = false
    ) -> some View {
        HStack(spacing: 16) {
            SettingCaption(title: title, detail: detail).frame(maxWidth: .infinity, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title).frame(width: 140)
            Text(degrees ? "\(Int(value.wrappedValue))°" : "\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }.padding(14)
    }

    private func informationRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 22)
            SettingCaption(title: title, detail: detail)
            Spacer(minLength: 0)
        }.padding(14)
    }
}

private struct SettingCaption: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .semibold)).padding(.leading, 1)
            content.background(
                Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon.frame(width: 15)
            configuration.title
        }
    }
}

private struct PageTransition: ViewModifier {
    var amount: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: amount * 4)
            .offset(y: amount * 6)
    }
}

/// Sample the desktop behind the window, rather than the opaque hosting view.
private struct SidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

@available(macOS 26.0, *)
private struct SidebarSelectionGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = 9
        view.tintColor = .controlAccentColor
        return view
    }
    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.tintColor = .controlAccentColor
    }
}
