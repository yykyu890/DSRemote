import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var pc: PCBridge
    @EnvironmentObject var coyote: CoyoteBLE
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("朗读回复", isOn: $settings.ttsEnabled)
                    VStack(alignment: .leading) {
                        Text("语速 \(String(format: "%.1f", settings.speakRate))x")
                        Slider(value: $settings.speakRate, in: 0.6...1.6, step: 0.1)
                    }
                } header: {
                    Text("语音")
                }

                Section {
                    TextField("接口地址", text: $settings.baseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("API Key", text: $settings.apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("对话模型", text: $settings.model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("识图模型（留空=对话模型）", text: $settings.visionModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("转写模型", text: $settings.asrModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("模型接口")
                } footer: {
                    Text("聊天、看图、语音转写都走这里。Key 只存在本机。")
                }

                Section {
                    Toggle("连接电脑（用于 OSR 动作）", isOn: $settings.usePC)
                    TextField("电脑地址", text: $settings.pcAddress)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    LabeledContent("状态", value: pc.connected ? "已连接" : "未连接")
                } header: {
                    Text("电脑（可选）")
                } footer: {
                    Text("不填也能用：聊天、郊狼、游戏都在手机上跑。只有让 OSR 动起来需要电脑。")
                }

                Section {
                    LabeledContent("郊狼", value: coyote.state.connected ? "已连接" : "未连接")
                    Stepper("强度上限 \(settings.coyoteMax)",
                            value: $settings.coyoteMax, in: 5...200, step: 5)
                } header: {
                    Text("郊狼")
                }

                Section {
                    TextEditor(text: $settings.persona)
                        .frame(minHeight: 140)
                        .font(.callout)
                } header: {
                    Text("角色设定")
                } footer: {
                    Text("这段会作为系统提示发给模型。")
                }

                Section {
                    Button("清空对话") {
                        NotificationCenter.default.post(name: .resetChat, object: nil)
                    }
                }
            }
            .navigationTitle("设置")
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

extension Notification.Name {
    static let resetChat = Notification.Name("resetChat")
}
