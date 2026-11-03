import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var backend: Backend
    @State private var draft = ""
    @State private var showMotion = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !backend.errorText.isEmpty {
                Text(backend.errorText)
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
        .onAppear { backend.connect() }
        .sheet(isPresented: $showMotion) {
            MotionSheet()
                .environmentObject(backend)
                .presentationDetents([.height(380)])
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(backend.state.estop ? Color.red
                      : backend.state.connected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text("她的节奏").font(.headline)
            Text(backend.state.mode == "hardware" ? "真机" : "模拟")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { backend.estop() }) {
                Text(backend.state.estop ? "解除" : "急停")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(backend.state.estop
                                ? Color.orange
                                : Color(red: 1, green: 0.3, blue: 0.62))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.14, green: 0.086, blue: 0.157))
    }

    // MARK: - 聊天

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(backend.messages) { message in
                        bubble(message).id(message.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: backend.messages.count) { _ in
                if let last = backend.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: Message) -> some View {
        switch message.who {
        case .sys:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    // MARK: - 快捷键

    private var quickBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("动作/强度") { showMotion = true }
                chip("轻一点") {
                    backend.motion(pattern: "stroke", intensity: 35,
                                   tempo: 50, seconds: 20)
                }
                chip("停") { backend.stopMotion() }
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
            TextField("说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .padding(11)
                .background(Color(red: 0.18, green: 0.11, blue: 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)

            Button {
                backend.send(draft)
                draft = ""
            } label: {
                Text("发送")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color(red: 1, green: 0.3, blue: 0.62))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.14, green: 0.086, blue: 0.157))
    }
}

// MARK: - 动作面板

struct PatternOption: Identifiable {
    let id: String
    let label: String
}

struct MotionSheet: View {
    @EnvironmentObject private var backend: Backend
    @Environment(\.dismiss) private var dismiss

    @State private var pattern = "stroke"
    @State private var intensity = 40.0
    @State private var tempo = 55.0
    @State private var seconds = 20.0

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
                Section {
                    Button("开始动作") {
                        backend.motion(pattern: pattern,
                                       intensity: Int(intensity),
                                       tempo: Int(tempo),
                                       seconds: Int(seconds))
                        dismiss()
                    }
                    Button("缓停", role: .destructive) {
                        backend.stopMotion()
                        dismiss()
                    }
                }
            }
            .navigationTitle("动作")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
