import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// Define constants for media keys
private let NX_KEYTYPE_PLAY: UInt32 = 16
private let NX_KEYSTATE_DOWN: UInt32 = 0x0A

@MainActor
struct ContentView: View {
    @StateObject var player = AudioPlayer.shared
    @State private var isDragging = false
    @State private var showingAbout = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Background with artwork
            if let track = player.currentTrack, !showingAbout {
                HStack(spacing: 0) {
                    // Left part with artwork and gradient
                    ZStack(alignment: .trailing) {
                        AsyncImage(url: track.artwork) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 128, height: 128)
                                    .clipped()
                                    .overlay(Color.black.opacity(0.5))
                                    .overlay(
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: Color.black.opacity(1), location: 0),
                                                .init(color: Color.black.opacity(0), location: 1)
                                            ]),
                                            startPoint: .trailing,
                                            endPoint: .leading
                                        )
                                        .blendMode(.destinationOut)
                                    )
                            default:
                                Color.clear
                            }
                        }
                    }
                    .frame(width: 128)
                    .compositingGroup()

                    Spacer()
                }
            }

            // Main content
            VStack(spacing: 0) {
                CustomTitleBar(player: player, showingAbout: $showingAbout)
                    .background(Color.clear)

                // Main content
                ZStack {
                    if let track = player.currentTrack {
                        NonDraggableView {
                            PlayerInterface(player: player, track: track)
                        }
                    } else {
                        DropZoneView(isDragging: $isDragging)
                    }
                }
                .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity, minHeight: 100, idealHeight: 100, maxHeight: 100)
                .background(Color.clear)
            }

            // About view overlay
            if showingAbout {
                AboutView(showingAbout: $showingAbout)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                    .transition(.move(edge: .top))
                    .zIndex(1)
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingAbout)
        .animation(.easeInOut(duration: 0.2), value: player.currentTrack != nil)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .onDrop(of: [.audio], isTargeted: $isDragging) { providers in
            let providers = Array(providers)
            Task { @MainActor in
                await handleDrop(providers)
            }
            return true
        }
        .focused($isFocused)
        .onAppear {
            isFocused = true
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49 { // Space key
                    player.togglePlayPause()
                    return nil
                }
                return event
            }
            MediaKeyHandler.shared.setCallback {
                Task { @MainActor in
                    player.togglePlayPause()
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                isFocused = true
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        // Create a sendable copy of providers
        let providersCopy = providers.map { provider -> (id: UUID, provider: NSItemProvider) in
            (UUID(), provider)
        }
        
        for (_, provider) in providersCopy {
            if let url = try? await loadItemURL(from: provider),
               AudioFormat.allExtensions.contains(url.pathExtension.lowercased()) {
                try? await player.load(url: url)
                break
            }
        }
    }

    private func loadItemURL(from provider: NSItemProvider) async throws -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.audio.identifier) { item, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }
}

@MainActor
struct PlayerInterface: View {
    @ObservedObject var player: AudioPlayer
    let track: Track
    @State private var showPlayIcon: Bool = false
    @State private var showRemainingTime: Bool = Settings.shared.showRemainingTime

    var body: some View {
        HStack(spacing: 15) {
            // Play/Pause button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    player.togglePlayPause()
                }
            }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .frame(width: 50)
                    .scaleEffect(showPlayIcon ? 0.8 : 1.0)
                    .animation(.spring(response: 0.2), value: player.isPlaying)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .onChange(of: player.isPlaying) { isPlaying in
                withAnimation(.spring(response: 0.2)) {
                    showPlayIcon = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.2)) {
                        showPlayIcon = false
                    }
                }
            }

            // Track info and waveform
            VStack(alignment: .leading, spacing: 8) {
                // Waveform
                HStack(spacing: 8) {
                    Button(action: {
                        showRemainingTime.toggle()
                        Settings.shared.showRemainingTime = showRemainingTime
                    }) {
                        Text(formatTime(showRemainingTime ? track.duration - player.currentTime : player.currentTime))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                    .buttonStyle(.plain)

                    WaveformView(
                        url: track.fileURL,
                        currentTime: player.currentTime,
                        duration: track.duration,
                        onSeek: { time in
                            player.seek(to: time)
                        }
                    )
                    .id(track.fileURL)
                    .frame(height: 30)

                    Text(formatTime(track.duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 45, alignment: .leading)
                        .padding(.trailing, -20)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return showRemainingTime && time != track.duration ? 
            String(format: "-%d:%02d", minutes, seconds) :
            String(format: "%d:%02d", minutes, seconds)
    }
}

struct CoverArtView: View {
    let track: Track
    let isPlaying: Bool
    let showPlayIcon: Bool

    var body: some View {
        ZStack {
            AsyncImage(url: track.artwork) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
            }

            if showPlayIcon || !isPlaying {
                Color.black.opacity(0.5)
                Image(systemName: isPlaying ? "pause.fill" : "pause.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 80, height: 80)
        .cornerRadius(6)
        .shadow(radius: 5)
    }
}

struct DropZoneView: View {
    @Binding var isDragging: Bool

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 30))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text("Drop audio file to open")
                    .font(.headline)
                Text("Supported formats: \(AudioFormat.formatsDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .scaleEffect(isDragging ? 1.05 : 1)
        .opacity(isDragging ? 1 : 0.7)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct AboutView: View {
    @Binding var showingAbout: Bool

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "MIMP"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content
            HStack(spacing: 15) {
                // Back button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingAbout = false
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)

                // Centered columns
                HStack(spacing: 40) {
                    // Left column - information
                    VStack(alignment: .center, spacing: 10) {
                        HStack(spacing: 12) {
                            if let appIcon = NSImage(named: "AppIcon") {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(10)
                                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appName)
                                    .font(.system(size: 20, weight: .bold))
                                Text("v\(appVersion)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Minimal Interface Music Player")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Text("© 2024")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }

                    // Right column - links
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach([
                            ("github-mark", "GitHub", "https://github.com/iampingvi/MIMP"),
                            ("cup.and.saucer.fill", "Buy me a coffee", "https://www.buymeacoffee.com/pingvi"),
                            ("globe", "Official Website", "https://iampingvi.github.io/PIMP")
                        ], id: \.1) { icon, text, urlString in
                            Link(destination: URL(string: urlString)!) {
                                HStack(spacing: 8) {
                                    if icon == "github-mark" {
                                        Image(icon)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: icon)
                                            .frame(width: 16)
                                    }
                                    Text(text)
                                        .underline()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .opacity(0.9)
                            .hover { hovering in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if let button = NSApp.keyWindow?.contentView?.hitTest(NSEvent.mouseLocation)?.enclosingScrollView {
                                        button.alphaValue = hovering ? 1 : 0.9
                                    }
                                }
                            }
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, 70)

                Spacer()
            }
            .frame(height: 100)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Footer text
            Text("Made with ♥︎ by PINGVI")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Add hover effect modifier
extension View {
    func hover(_ handler: @escaping (Bool) -> Void) -> some View {
        self.onHover { hovering in
            handler(hovering)
        }
    }
}

struct NonDraggableView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(DisableDraggingView())
    }
}

struct DisableDraggingView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableNSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class NonDraggableNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }
    
    // Переопределяем этот метод, чтобы предотвратить перетаскивание
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
    
    // Перехватываем событие мыши, чтобы предотвратить его распространение
    override func mouseDown(with event: NSEvent) {
        // Не передаем событие дальше
    }
}

#Preview {
    ContentView()
}
