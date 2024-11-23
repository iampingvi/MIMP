import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CoreServices

// Define constants for media keys
private let NX_KEYTYPE_PLAY: UInt32 = 16
private let NX_KEYSTATE_DOWN: UInt32 = 0x0A

@MainActor
struct ContentView: View {
    @StateObject var player = AudioPlayer.shared
    @State private var isDragging = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isFocused: Bool
    @State private var seekTimer: Timer?
    @State private var isSeekingForward = false
    @State private var isSeekingBackward = false
    @State private var showingFirstLaunch = Settings.shared.isFirstLaunch
    @StateObject private var updateManager = UpdateManager.shared
    @State private var pressedKeys: Set<String> = []
    @State private var lastKeyPressTime: Date = Date()
    @State private var isCompactMode = Settings.shared.isCompactMode
    @State private var keyMonitor: Any?
    @State private var showingAbout = false

    var body: some View {
        ZStack(alignment: .top) {
            // Background blur
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
            .zIndex(1)

            // Background with artwork
            if let track = player.currentTrack, !showingFirstLaunch {
                HStack(spacing: 0) {
                    // Left part with artwork and gradient
                    ZStack(alignment: .top) {
                        AsyncImage(url: track.artwork) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(
                                        width: isCompactMode ? 80 : 128, 
                                        height: isCompactMode ? 80 : 120,
                                        alignment: .top
                                    )
                                    .clipped()
                                    .overlay(Color.black.opacity(0.5))
                            case .empty, .failure:
                                // Default macOS-style music icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(
                                            width: isCompactMode ? 80 : 128, 
                                            height: isCompactMode ? 80 : 120,
                                            alignment: .top
                                        )
                                    Image(systemName: "music.note")
                                        .font(.system(size: isCompactMode ? 24 : 40))
                                        .foregroundColor(.gray)
                                }
                                .overlay(Color.black.opacity(0.5))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .frame(width: isCompactMode ? 80 : 128, alignment: .top)
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
                    .compositingGroup()
                    .clipped()
                    .transaction { transaction in
                        transaction.animation = .spring(response: 0.3, dampingFraction: 0.8)
                    }

                    Spacer()
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .zIndex(2)
            }

            // Main content
            VStack(spacing: 0) {
                CustomTitleBar(player: player, showingAbout: $showingAbout)
                    .background(Color.clear)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                
                ZStack {
                    if let track = player.currentTrack {
                        NonDraggableView {
                            PlayerInterface(player: player, track: track)
                        }
                    } else if !Settings.shared.launchedWithFile && !player.isLoading {
                        DropZoneView(isDragging: $isDragging, isCompactMode: isCompactMode)
                    }
                }
                .frame(
                    minWidth: 600, 
                    idealWidth: 800, 
                    maxWidth: .infinity, 
                    minHeight: isCompactMode ? 52 : 92,
                    idealHeight: isCompactMode ? 52 : 92,
                    maxHeight: isCompactMode ? 52 : 92
                )
                .animation(.easeInOut(duration: 0.3), value: isCompactMode)
            }
            .frame(height: isCompactMode ? 80 : 120)
            .background(Color.clear)
            .zIndex(3)
            
            // Overlays
            Group {
                if showingAbout {
                    AboutView(showingAbout: $showingAbout, isCompactMode: isCompactMode)
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                        .frame(height: isCompactMode ? 80 : 120)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
                
                if showingFirstLaunch {
                    FirstLaunchView(isPresented: $showingFirstLaunch)
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                        .frame(height: 120)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
                
                if updateManager.showingUpdate {
                    UpdateView()
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                        .frame(height: isCompactMode ? 80 : 120)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .zIndex(1000)
        }
        .frame(height: isCompactMode ? 80 : 120)
        .clipped()
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
            HotKeys.shared.setBindings(showingAbout: $showingAbout, updateManager: updateManager)
            keyMonitor = HotKeys.shared.setupKeyboardMonitoring(for: player)
            
            MediaKeyHandler.shared.setCallbacks(
                playPause: {
                    Task { @MainActor in
                        player.togglePlayPause()
                    }
                },
                stop: {
                    Task { @MainActor in
                        player.stop()
                    }
                }
            )
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                isFocused = true
            }
        }
        .onDisappear {
            stopSeekTimer()
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        .onAppear {
            // If launched with file but no track is loaded yet,
            // keep the launchedWithFile flag true
            if Settings.shared.launchedWithFile && player.currentTrack == nil {
                Settings.shared.launchedWithFile = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            isCompactMode = Settings.shared.isCompactMode
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

    private func startSeekTimer(forward: Bool) {
        stopSeekTimer()
        
        // Initial seek
        Task { @MainActor in
            player.seekRelative(forward ? 3 : -3)
        }
        
        // Start timer for continuous seeking
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak player] _ in
            Task { @MainActor in
                player?.seekRelative(forward ? 2 : -2)
            }
        }
    }
    
    private func stopSeekTimer() {
        seekTimer?.invalidate()
        seekTimer = nil
    }
    
    private func resetDefaultPlayer() {
        print("\n=== Resetting MIMP Default Player Settings ===")
        
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue) {
                print("\nResetting .\(format.rawValue)")
                
                let status = LSSetDefaultRoleHandlerForContentType(
                    type.identifier as CFString,
                    LSRolesMask.all,
                    "com.apple.quicktimeplayer" as CFString  // Сбрасываем на QuickTime Player
                )
                
                print(status == noErr ? "✓ Reset successful" : "✗ Reset failed")
            }
        }
        
        // Сбрасываем настройку в Settings
        Settings.shared.isDefaultPlayerSet = false
        
        print("\n=== Reset Complete ===\n")
    }
}

@MainActor
struct PlayerInterface: View {
    @ObservedObject var player: AudioPlayer
    let track: Track
    @State private var showPlayIcon: Bool = false
    @State private var showRemainingTime: Bool = Settings.shared.showRemainingTime
    @State private var isCompactMode = Settings.shared.isCompactMode

    var body: some View {
        VStack(spacing: isCompactMode ? 8 : 15) {
            // Показываем аудио инормацию только если не в компактном режиме
            if !isCompactMode {
                if let audioInfo = player.audioInfo {
                    audioInfo.view()
                        .opacity(player.isLoading ? 0 : 1)
                        .padding(.top, 8) // Добавляем отступ сверху
                        .transition(.move(edge: .top).combined(with: .opacity)) // Добавляем анимацию
                }
            }
            
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
                }
                .buttonStyle(.plain)
                .scaleEffect(showPlayIcon ? 0.8 : 1.0)
                .animation(.spring(response: 0.2), value: player.isPlaying)
                .padding(.leading, isCompactMode ? 8 : 20)
                .transition(.scale.combined(with: .opacity)) // Добавляем анимацию

                // Track info and waveform
                VStack(alignment: .leading, spacing: 8) {
                    // Waveform
                    HStack(spacing: isCompactMode ? 4 : 8) {
                        Button(action: {
                            showRemainingTime.toggle()
                            Settings.shared.showRemainingTime = showRemainingTime
                        }) {
                            Text(formatTime(showRemainingTime ? track.duration - player.currentTime : player.currentTime))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: isCompactMode ? 35 : 45, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, isCompactMode ? -15 : -30)
                        .transition(.scale.combined(with: .opacity))

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
                        .padding(.horizontal, isCompactMode ? 4 : 6)
                        .transition(.opacity)

                        Text(formatTime(track.duration))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: isCompactMode ? 35 : 45, alignment: .leading)
                            .padding(.trailing, isCompactMode ? -8 : -20)
                            .transition(.scale.combined(with: .opacity))
                    }
                    .opacity(player.isLoading ? 0 : 1)
                }
            }
            .padding(.horizontal, isCompactMode ? 4 : 12)
            .padding(.vertical, isCompactMode ? 2 : 8)
        }
        .animation(.easeInOut(duration: 0.3), value: isCompactMode) // Анимация для всего интерфейса
        .onChange(of: isCompactMode) { newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                // Обновляем состояние при изменении режима
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isCompactMode = Settings.shared.isCompactMode
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        // Ограничиваем время между 0 и длительностью трека
        let clampedTime = min(max(time, 0), track.duration)
        let minutes = Int(clampedTime) / 60
        let seconds = Int(clampedTime) % 60
        return showRemainingTime && clampedTime != track.duration ? 
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
                // Default macOS-style music icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                    Image(systemName: "music.note")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
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
    let isCompactMode: Bool
    
    var body: some View {
        Group {
            HStack(spacing: isCompactMode ? 15 : 20) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: isCompactMode ? 24 : 30))
                    .foregroundColor(.white.opacity(isDragging ? 1 : 0.7))

                VStack(alignment: .leading, spacing: isCompactMode ? 3 : 5) {
                    Text("Drop audio file to open")
                        .font(.system(size: isCompactMode ? 11 : 13, weight: .medium))
                    Text("Supported formats: \(AudioFormat.formatsDescription)")
                        .font(.system(size: isCompactMode ? 9 : 11))
                }
            }
            .foregroundColor(.white.opacity(isDragging ? 1 : 0.7))
            .padding(isCompactMode ? 20 : 40)
            .transaction { transaction in
                transaction.animation = nil  // Отключаем анимацию для изменения размеров
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDragging) // Анимация прозрачности для всей группы
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

// Добавляем структуру NonDraggableView
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
    
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
    
    override func mouseDown(with event: NSEvent) {
        // Не передаем событие дальше
    }
}

// Добавляем расширение View дл hover эффекта
extension View {
    func hover(_ handler: @escaping (Bool) -> Void) -> some View {
        self.onHover { hovering in
            handler(hovering)
        }
    }
}

// Добавляем расширение для условного применения моификаторов
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
}
