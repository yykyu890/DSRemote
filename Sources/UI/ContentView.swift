import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var engine: ChatEngine
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var pc: PCBridge
    @EnvironmentObject var coyote: CoyoteBLE
    @EnvironmentObject var game: GameStore
    @EnvironmentObject var recorder: Recorder

    @State private var draft = ""
    @State private var showSettings = false
    @State private var showCoyote = false
    @State private var showGame = false
    @State private var showMotion = false
    @State private var transcribing = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !engine.errorText.isEmpty {
                Text(engine.errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
            chat
            quickBar
            inputBar
        }
        .background(Color(red: 0.106, green: 0.063, blue: 0.114).ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView().presentationDetents([.large])
        }
        .sheet(isPresented: $showCoyote) {
            CoyoteSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showGame) {
            GameSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showMotion) {
            MotionSheet().presentationDetents([.height(400)])
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetChat)) { _ in
            engine.reset()
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text("她的节奏").font(.headline)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).foregroundStyle(.secondary)
            }
            if settings.usePC {
                Button {
                    Task {
                        await pc.toggleEstop()
                    }
                } label: {
                    Text(pc.estop ? "解除" : "急停")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(pc.estop ? Color.orange
                                    : Color(red: 1, green: 0.3, blue: 0.62))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.14, green: 0.086, blue: 0.157))
    }

    private var statusColor: Color {
        if settings.usePC && pc.estop { return .red }
        if coyote.state.connected { return .green }
        if settings.usePC && pc.connected { return .green }
        return .orange
    }

    private var statusText: String {
        var bits: [String] = []
        if coyote.state.connected { bits.append("郊狼") }
        if settings.usePC { bits.append(pc.connected ? "电脑" : "电脑未连") }
        if game.playing { bits.append("游戏中") }
        return bits.isEmpty ? "未连接设备" : bits.joined(separator: " · ")
    }

    // MARK: - 聊天

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(engine.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if engine.busy {
                        Text("…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .onChange(of: engine.messages.count) { _ in
                if let last = engine.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: Message) -> some View {
        switch message.who {
        case .sys:
            Text(message.text).font(.caption).foregroundStyle(.secondary)
        case .me, .her:
            HStack {
                if message.who == .me { Spacer(minLength: 40) }
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.who == .me
                                ? Color(red: 0.61, green: 0.89, blue: 0.56)
                                : Color.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if message.who == .her { Spacer(minLength: 40) }
            }
        }
    }

    // MARK: - 快捷

    private var quickBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(game.playing ? "游戏进行中" : "游戏") { showGame = true }
                chip(coyote.state.connected ? "郊狼 ✓" : "郊狼") { showCoyote = true }
                if settings.usePC {
                    chip("动作") { showMotion = true }
                    chip("停") {
                        Task { _ = await pc.stopMotion() }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.14, green: 0.086, blue: 0.157))
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(red: 0.18, green: 0.11, blue: 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.white)
    }

    // MARK: - 输入

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await toggleRecord() }
            } label: {
                Image(systemName: recorder.recording ? "stop.circle.fill" : "mic.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(recorder.recording ? .red : .secondary)
            }
            .disabled(transcribing)

            TextField("说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .padding(11)
                .background(Color(red: 0.18, green: 0.11, blue: 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)

            Button {
                engine.send(draft)
                draft = ""
            } label: {
                Text(transcribing ? "…" : "发送")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(red: 1, green: 0.3, blue: 0.62))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || transcribing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.14, green: 0.086, blue: 0.157))
    }

    // MARK: - 语音

    private func toggleRecord() async {
        if recorder.recording {
            guard let wav = recorder.stop() else { return }
            transcribing = true
            defer { transcribing = false }
            do {
                let client = LLMClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
                let text = try await client.transcribe(wav: wav, model: settings.asrModel)
                if text.isEmpty {
                    engine.errorText = "没听清，再说一次"
                } else {
                    engine.send(text)
                }
            } catch {
                engine.errorText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        } else {
            guard await recorder.requestPermission() else {
                engine.errorText = "麦克风权限被拒绝（设置 → 她的节奏 → 麦克风）"
                return
            }
            recorder.start()
        }
    }
}

// MARK: - 动作面板（走电脑）

struct PatternOption: Identifiable {
    let id: String
    let label: String
}

struct MotionSheet: View {
    @EnvironmentObject var pc: PCBridge
    @Environment(\.dismiss) private var dismiss

    @State private var pattern = "stroke"
    @State private var intensity = 40.0
    @State private var tempo = 55.0
    @State private var seconds = 20.0
    @State private var note = ""

    private let patterns: [PatternOption] = [
        PatternOption(id: "stroke", label: "抽送"),
        PatternOption(id: "surge", label: "推进"),
        PatternOption(id: "sway", label: "摇摆"),
        PatternOption(id: "twist", label: "扭转"),
        PatternOption(id: "roll", label: "翻滚"),
        PatternOption(id: "pitch", label: "俯仰"),
    ]

    var body: some View {
        NavigationView {
            Form {
                Picker("动作", selection: $pattern) {
                    ForEach(patterns) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                VStack(alignment: .leading) {
                    Text("强度 \(Int(intensity))%")
                    Slider(value: $intensity, in: 1...100)
                }
                VStack(alignment: .leading) {
                    Text("速度 \(Int(tempo))%")
                    Slider(value: $tempo, in: 10...100)
                }
                VStack(alignment: .leading) {
                    Text("时长 \(Int(seconds)) 秒")
                    Slider(value: $seconds, in: 5...300, step: 5)
                }
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
                Section {
                    Button("开始动作") {
                        Task {
                            note = await pc.motion(pattern: pattern,
                                                   intensity: Int(intensity),
                                                   tempo: Int(tempo),
                                                   seconds: Int(seconds))
                        }
                    }
                    Button("缓停", role: .destructive) {
                        Task { note = await pc.stopMotion() }
                    }
                }
            }
            .navigationTitle("动作")
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
