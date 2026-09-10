import SwiftUI
import MetalKit

struct MetalPreview: NSViewRepresentable {
    let model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model:model) }
    func makeNSView(context:Context) -> MTKView { context.coordinator.renderer?.makeView() ?? MTKView() }
    func updateNSView(_ view:MTKView,context:Context) {}
    static func dismantleNSView(_ view:MTKView,coordinator:Coordinator) { view.isPaused=true; view.delegate=nil }
    @MainActor final class Coordinator {
        let renderer: BendRenderer?
        init(model:AppModel) {
            renderer = try? BendRenderer(frames:model.previewFrames)
            renderer?.parameters = { [weak model] in model?.parameters(preview:true) ?? BendParameters() }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = "Appearance"
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:6) {
                Label("BendMac",systemImage:"macbook").font(.title3.weight(.semibold)).padding(.bottom,25).padding(.horizontal,12)
                sidebar("General",icon:"gearshape")
                Text("SETTINGS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top,20).padding(.leading,12)
                sidebar("Appearance",icon:"circle.lefthalf.filled")
                Spacer()
                Label(model.sensorAngle == nil ? "Sensor unavailable" : "Lid sensor connected",systemImage:model.sensorAngle == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(model.sensorAngle == nil ? .orange : .green).padding(.horizontal,10)
                Text("Native. Local. Just a little bend.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,10)
            }.padding(16).frame(width:176).frame(maxHeight:.infinity).background(.ultraThinMaterial)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Label(tab,systemImage:tab == "Appearance" ? "circle.lefthalf.filled" : "gearshape").font(.title2.weight(.semibold))
                    if tab == "Appearance" { appearance } else { general }
                }.padding(28).frame(maxWidth:.infinity,alignment:.leading)
            }.background(Color(nsColor:.windowBackgroundColor))
        }.frame(width:850,height:750)
    }
    private func sidebar(_ title:String,icon:String) -> some View {
        Button { tab=title } label: {
            Label(title,systemImage:icon).font(.body.weight(.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(10)
                .background(tab == title ? Color.accentColor.opacity(0.16) : .clear,in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var appearance: some View {
        VStack(spacing:0) {
            ZStack(alignment:.top) {
                MetalPreview(model:model).aspectRatio(1.6,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:10)).padding(9)
                RoundedRectangle(cornerRadius:4).fill(.black).frame(width:90,height:13).padding(.top,8)
                VStack { Spacer(); Button { model.playPreview() } label: {
                    Image(systemName:model.previewPlaying ? "waveform" : "play.fill").font(.title2).frame(width:48,height:48).background(.ultraThinMaterial,in:Circle())
                }.buttonStyle(.plain).help("Play a full fold and unfold preview").accessibilityLabel("Play fold animation"); Spacer() }
            }.background(.black,in:RoundedRectangle(cornerRadius:18))
            UnevenRoundedRectangle(bottomLeadingRadius:6,bottomTrailingRadius:6).fill(Color(nsColor:.systemGray)).frame(height:12).padding(.horizontal,-15)
        }.padding(.horizontal,38)
        HStack {
            Text("\(Int(model.previewAngle))°").monospacedDigit().foregroundStyle(.secondary).frame(width:42)
            Slider(value:$model.previewAngle,in:12...135,onEditingChanged:{ _ in model.previewPlaying=false }).accessibilityLabel("Preview lid angle")
            Text("Preview angle").font(.callout).foregroundStyle(.secondary)
        }
        VStack(alignment:.leading,spacing:10) {
            Text("Style").font(.headline)
            HStack(spacing:12) {
                styleCard("Silk",index:0,description:"Soft and fluid",icon:"wind")
                styleCard("Shade",index:1,description:"Deeper shadows",icon:"moon.fill")
                styleCard("Frost",index:2,description:"Diffused glass",icon:"snowflake")
            }
        }
        VStack(spacing:0) {
            settingSlider("Perspective",value:$model.perspective)
            Divider().padding(.horizontal,16)
            settingSlider("Variable blur",value:$model.blur)
            Divider().padding(.horizontal,16)
            settingSlider("Shadow",value:$model.shadow)
        }.background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:12))
        HStack {
            Image(systemName:"info.circle").foregroundStyle(.secondary)
            Text("The preview uses the same Metal effect as your desktop.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Reset") { model.perspective=0.65; model.blur=0.9; model.shadow=0.35; model.style=0; model.clearAngle=105 }
        }
    }
    private func styleCard(_ name:String,index:Int,description:String,icon:String) -> some View {
        Button { model.style=index } label: {
            VStack(spacing:8) {
                Image(systemName:icon).font(.title2).frame(height:28)
                Text(name).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity).padding(.vertical,15)
                .background(model.style == index ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(model.style == index ? Color.accentColor : .clear,lineWidth:2))
        }.buttonStyle(.plain).accessibilityAddTraits(model.style == index ? .isSelected : [])
    }
    private func settingSlider(_ name:String,value:Binding<Double>) -> some View {
        HStack {
            Text(name).frame(width:110,alignment:.leading)
            Slider(value:value,in:0...1).accessibilityLabel(name)
            Text("\(Int(value.wrappedValue*100))%").monospacedDigit().foregroundStyle(.secondary).frame(width:42,alignment:.trailing)
        }.padding(14)
    }
    @ViewBuilder private var general: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Image(systemName:"macbook").font(.system(size:34)).foregroundStyle(Color.accentColor)
                VStack(alignment:.leading,spacing:3) {
                    Text(model.enabled ? "Your desktop is ready to bend" : "Give your desktop a little flexibility").font(.headline)
                    Text("Tilt, blur, and shade as your lid closes.").foregroundStyle(.secondary)
                }
            }
            Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button(model.starting ? "Connecting…" : model.enabled ? "Pause effect" : "Enable desktop effect") {
                    if model.enabled { model.disable() } else { model.enable() }
                }.buttonStyle(.borderedProminent).disabled(model.starting)
                if model.enabled { Text("Esc pauses instantly").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:12))
        GroupBox("Lid behavior") {
            VStack(alignment:.leading,spacing:18) {
                HStack {
                    Toggle("Follow physical lid",isOn:$model.followLid)
                    Spacer()
                    Text(model.sensorAngle.map { "\(Int($0))°" } ?? "Unavailable").monospacedDigit().foregroundStyle(.secondary)
                }
                if !model.followLid {
                    HStack {
                        Text("Desktop angle")
                        Slider(value:$model.manualAngle,in:12...135).accessibilityLabel("Live desktop angle")
                        Text("\(Int(model.manualAngle))°").monospacedDigit().frame(width:40)
                    }
                }
                HStack {
                    Text("Clear at")
                    Slider(value:$model.clearAngle,in:80...135).accessibilityLabel("Lid angle at which desktop clears")
                    Text("\(Int(model.clearAngle))°").monospacedDigit().frame(width:40)
                }
                Text("Above this angle your desktop returns to normal. Only the built-in display bends.").font(.caption).foregroundStyle(.secondary)
                Toggle("Play a soft sound when the desktop clears",isOn:$model.sound)
            }.padding(12)
        }
        GroupBox("Screen Recording") {
            VStack(alignment:.leading,spacing:12) {
                Text("macOS needs your permission to show a live view of the desktop. Frames stay in memory on this Mac; no audio is captured and nothing is saved or uploaded.").font(.callout).foregroundStyle(.secondary)
                Button("Open Screen Recording settings…") {
                    NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }.padding(12)
        }
        Text("BendMac · Free and open source. Inspired by Bendy.\nSwift • AppKit • ScreenCaptureKit • Metal\nThe lid sensor report is undocumented and may vary between macOS versions.").font(.caption).foregroundStyle(.secondary)
    }
}
