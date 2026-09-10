import MetalKit
import SwiftUI

struct MetalPreview: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> MTKView {
        context.coordinator.renderer?.makeView() ?? MTKView()
    }
    func updateNSView(_ view: MTKView, context: Context) {}
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
    @State private var page = SettingsPage.appearance
    @State private var history: [SettingsPage] = []
    @State private var forwardHistory: [SettingsPage] = []

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.primary.opacity(0.025))
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
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        }
        .frame(minWidth: 740, idealWidth: 800, minHeight: 670, idealHeight: 720)
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
                        .background(
                            page == item ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 7)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Text("VERSION \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.top, 12)
            Spacer()
            Button(action: updates.checkForUpdates) {
                Label(
                    updates.availableVersion == nil ? "Check for updates" : "Update available",
                    systemImage: "arrow.down.circle"
                )
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    updates.availableVersion == nil ? Color.clear : Color.blue.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(updates.availableVersion == nil ? Color.secondary : Color.blue)
            .disabled(!updates.canCheckForUpdates)
            HStack(spacing: 6) {
                Circle().fill(model.enabled ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text(model.enabled ? "Effect enabled" : "Effect paused")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .padding(.bottom, 12)
        .frame(width: 176)
        .background(.ultraThinMaterial)
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
            SettingsSection("Preview") {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text("Preview the fold").font(.system(size: 13, weight: .semibold))
                        Text("Play the animation, or move the slider to try it yourself.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    ZStack(alignment: .bottom) {
                        MetalPreview(model: model)
                            .aspectRatio(1.6, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 19))
                        Button {
                            if model.previewPlaying {
                                model.previewPlaying = false
                            } else {
                                model.playPreview()
                            }
                        } label: {
                            Label(
                                model.previewPlaying ? "Pause" : "Play fold",
                                systemImage: model.previewPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(PreviewPillStyle(reduceMotion: reduceMotion))
                        .accessibilityLabel(model.previewPlaying ? "Pause fold preview" : "Play fold preview")
                        .padding(.bottom, 16)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .frame(maxWidth: 280)
                    HStack(spacing: 10) {
                        Image(systemName: "macbook").foregroundStyle(.secondary)
                        Slider(
                            value: $model.previewAngle, in: 12...135,
                            onEditingChanged: { _ in model.previewPlaying = false }
                        )
                        .accessibilityLabel("Preview lid angle")
                        Text("\(Int(model.previewAngle))°").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(maxWidth: 280)
                    .font(.system(size: 11))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
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
                model.perspective = 1
                model.blur = 0.9
                model.shadow = 0.35
                model.style = 0
                model.clearAngle = 105
            } label: {
                Label("Reset to default", systemImage: "arrow.uturn.backward")
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
                            get: { model.enabled },
                            set: { enabled in
                                if enabled { model.enable() } else { model.disable() }
                            })
                    ) {
                        SettingCaption(
                            title: model.starting ? "Connecting…" : "Enable BendMac",
                            detail: "Let your desktop follow the lid.")
                    }
                    .toggleStyle(.switch).controlSize(.small).disabled(model.starting).padding(14)
                    rowDivider
                    Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                        .textSelection(.enabled).padding(14)
                }
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
            content.background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.035)))
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

private struct PreviewPillStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.8))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(.white.opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
