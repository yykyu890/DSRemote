import SwiftUI

struct CoyoteSheet: View {
    @EnvironmentObject var coyote: CoyoteBLE
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var wave = Waveform.presets[0]
    @State private var seconds = 5.0
    @State private var strength = 10.0

    var body: some View {
        NavigationView {
            Form {
                Section {
                    if coyote.state.connected {
                        Label("已连接", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("A 通道强度", value: "\(coyote.state.strengthA)")
                        LabeledContent("B 通道强度", value: "\(coyote.state.strengthB)")
                        if !coyote.state.playing.isEmpty {
                            LabeledContent("正在播放", value: coyote.state.playing)
                        }
                        Button("断开", role: .destructive) { coyote.disconnect() }
                    } else {
                        Button(coyote.scanning ? "扫描中…" : "扫描郊狼") {
                            coyote.startScan()
                        }
                        ForEach(coyote.found) { device in
                            Button {
                                coyote.connect(device.id)
                            } label: {
                                HStack {
                                    Text(device.name)
                                    Spacer()
                                    Text("连接").foregroundStyle(.blue)
                                }
                            }
                        }
                        if coyote.found.isEmpty && !coyote.scanning {
                            Text("先让郊狼开机，再点扫描")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !coyote.errorText.isEmpty {
                        Text(coyote.errorText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("设备")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("强度 \(Int(strength))（上限 \(settings.coyoteMax)）")
                        Slider(value: $strength, in: 0...Double(settings.coyoteMax), step: 1)
                    }
                    HStack {
                        Button("A 通道设为") {
                            coyote.setStrength("A", value: Int(strength))
                        }
                        Spacer()
                        Button("B 通道设为") {
                            coyote.setStrength("B", value: Int(strength))
                        }
                    }
                    .disabled(!coyote.state.connected)
                    HStack {
                        Button("A +5") { coyote.setStrength("A", value: 5, mode: "inc") }
                        Button("A -5") { coyote.setStrength("A", value: 5, mode: "dec") }
                        Spacer()
                        Button("全部归零", role: .destructive) {
                            coyote.setStrength("A", value: 0)
                            coyote.setStrength("B", value: 0)
                        }
                    }
                    .disabled(!coyote.state.connected)
                } header: {
                    Text("强度")
                }

                Section {
                    Picker("波形", selection: $wave) {
                        ForEach(Waveform.presets) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("时长 \(Int(seconds)) 秒")
                        Slider(value: $seconds, in: 1...50, step: 1)
                    }
                    HStack {
                        Button("A 通道播放") {
                            coyote.play("A", waveform: wave, seconds: seconds)
                        }
                        Spacer()
                        Button("B 通道播放") {
                            coyote.play("B", waveform: wave, seconds: seconds)
                        }
                    }
                    .disabled(!coyote.state.connected)
                    Button("停止输出", role: .destructive) {
                        coyote.stopMotor()
                    }
                    .disabled(!coyote.state.connected)
                } header: {
                    Text("波形")
                } footer: {
                    Text("波形存在手机本地，不经过网络。强度上限可以在设置里改。")
                }
            }
            .navigationTitle("郊狼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
