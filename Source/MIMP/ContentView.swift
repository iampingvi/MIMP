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
    @State private var showingAbout = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isFocused: Bool
    @StateObject private var themeManager = ThemeManager.shared
    @State private var seekTimer: Timer?
    @State private var isSeekingForward = false
    @State private var isSeekingBackward = false
    @State private var showingFirstLaunch = Settings.shared.isFirstLaunch

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

            // Add first launch overlay
            if showingFirstLaunch {
                FirstLaunchView(isPresented: $showingFirstLaunch)
                    .background(VisualEffectView(
                        material: themeManager.isRetroMode ? .windowBackground : .hudWindow,
                        blendingMode: .behindWindow
                    ))
                    .transition(AnyTransition.move(edge: .top))
                    .zIndex(1)
            }
        }
        .background(
            VisualEffectView(
                material: themeManager.isRetroMode ? .windowBackground : .hudWindow,
                blendingMode: .behindWindow
            )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingAbout)
        .animation(.easeInOut(duration: 0.2), value: player.currentTrack != nil)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingFirstLaunch)
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
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                switch event.keyCode {
                case 49: // Space key
                    player.togglePlayPause()
                    return nil
                case 123: // Left Arrow
                    if !isSeekingBackward {
                        isSeekingBackward = true
                        startSeekTimer(forward: false)
                    }
                    return nil
                case 124: // Right Arrow
                    if !isSeekingForward {
                        isSeekingForward = true
                        startSeekTimer(forward: true)
                    }
                    return nil
                case 126: // Up Arrow
                    player.adjustVolume(by: 0.05)
                    return nil
                case 125: // Down Arrow
                    player.adjustVolume(by: -0.05)
                    return nil
                default:
                    return event
                }
            }
            
            NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [self] event in
                switch event.keyCode {
                case 123: // Left Arrow
                    isSeekingBackward = false
                    stopSeekTimer()
                case 124: // Right Arrow
                    isSeekingForward = false
                    stopSeekTimer()
                default:
                    break
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
        .onDisappear {
            stopSeekTimer()
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
}

@MainActor
struct PlayerInterface: View {
    @ObservedObject var player: AudioPlayer
    let track: Track
    @State private var showPlayIcon: Bool = false
    @State private var showRemainingTime: Bool = Settings.shared.showRemainingTime
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack(spacing: 15) {
            // Play/Pause button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    player.togglePlayPause()
                }
            }) {
                if themeManager.isRetroMode {
                    ZStack {
                        Rectangle()
                            .stroke(Color.retroText, lineWidth: 1)
                            .frame(width: 30, height: 30)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color.retroText)
                    }
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .frame(width: 50)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(showPlayIcon ? 0.8 : 1.0)
            .animation(.spring(response: 0.2), value: player.isPlaying)
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
                            .font(.system(
                                size: 10, 
                                weight: .medium, 
                                design: themeManager.isRetroMode ? .monospaced : .monospaced
                            ))
                            .foregroundColor(Color.retroText.opacity(0.7))
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
                        .font(.system(
                            size: 10, 
                            weight: .medium, 
                            design: themeManager.isRetroMode ? .monospaced : .monospaced
                        ))
                        .foregroundColor(Color.retroText.opacity(0.7))
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
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack(spacing: 20) {
            if themeManager.isRetroMode {
                Text("[]")
                    .font(.system(size: 30, design: .monospaced))
                    .foregroundColor(Color.retroText.opacity(0.7))
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 30))
                    .foregroundColor(Color.retroText.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Drop audio file to open")
                    .font(.system(
                        size: 13,
                        weight: .medium,
                        design: themeManager.isRetroMode ? .monospaced : .default
                    ))
                    .foregroundColor(Color.retroText)
                Text(themeManager.isRetroMode ? 
                    "Supported formats: [\(AudioFormat.formatsDescription)]" :
                    "Supported formats: (\(AudioFormat.formatsDescription))")
                    .font(.system(
                        size: 11,
                        design: themeManager.isRetroMode ? .monospaced : .default
                    ))
                    .foregroundColor(Color.retroText.opacity(0.7))
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
    @StateObject private var themeManager = ThemeManager.shared

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
                    Group {
                        if themeManager.isRetroMode {
                            ZStack {
                                Rectangle()
                                    .stroke(Color.retroText, lineWidth: 1)
                                    .frame(width: 24, height: 24)
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.retroText)
                            }
                        } else {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)

                // Content columns
                HStack(spacing: 30) {
                    // Column 1 - App Info
                    VStack(alignment: .center, spacing: 8) {
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .cornerRadius(themeManager.isRetroMode ? 0 : 15)
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .onTapGesture {
                                    themeManager.handleLogoClick()
                                }
                        }
                    }
                    .frame(width: 120)

                    // Column 2 - Description
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(appName)
                                .font(.system(
                                    size: 14,
                                    weight: .medium,
                                    design: themeManager.isRetroMode ? .monospaced : .default
                                ))
                                .foregroundColor(Color.retroText)
                            Text(themeManager.isRetroMode ? "[\(appVersion)]" : "(\(appVersion))")
                                .font(.system(
                                    size: 9,
                                    design: themeManager.isRetroMode ? .monospaced : .default
                                ))
                                .foregroundColor(Color.retroText.opacity(0.7))
                                .offset(y: -2)
                        }
                        .padding(.bottom, 2)
                        
                        Text("Minimal Interface\nMusic Player")
                            .font(.system(
                                size: 11,
                                design: themeManager.isRetroMode ? .monospaced : .default
                            ))
                            .foregroundColor(Color.retroText.opacity(0.7))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(width: 140, alignment: .leading)

                    // Column 3 - Links
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach([
                            ("github-mark", "GitHub", "https://github.com/iampingvi/MIMP"),
                            ("cup.and.saucer.fill", "Support", "https://www.buymeacoffee.com/pingvi"),
                            ("globe", "Website", "https://iampingvi.github.io/MIMP")
                        ], id: \.1) { icon, text, urlString in
                            Link(destination: URL(string: urlString)!) {
                                HStack(spacing: 6) {
                                    if icon == "github-mark" {
                                        Image(icon)
                                            .resizable()
                                            .frame(width: 14, height: 14)
                                            .if(themeManager.isRetroMode) { view in
                                                view.colorMultiply(Color.retroText)
                                            }
                                    } else {
                                        Image(systemName: icon)
                                            .frame(width: 14)
                                            .font(.system(size: 12))
                                    }
                                    Text(text)
                                        .font(.system(
                                            size: 12,
                                            design: themeManager.isRetroMode ? .monospaced : .default
                                        ))
                                        .underline()
                                }
                                .foregroundColor(Color.retroText)
                                .contentShape(Rectangle())
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
                    .frame(width: 120)

                    // Column 4 - Credits
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Made with ♥︎ by PINGVI")
                            .font(.system(
                                size: 11,
                                design: themeManager.isRetroMode ? .monospaced : .default
                            ))
                            .foregroundColor(Color.retroText.opacity(0.7))
                            .fixedSize(horizontal: true, vertical: false)
                        Text("© 2024")
                            .font(.system(
                                size: 11,
                                design: themeManager.isRetroMode ? .monospaced : .default
                            ))
                            .foregroundColor(Color.retroText.opacity(0.7))
                            .padding(.top, 2)
                    }
                    .frame(width: 160)
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, 20)
            }
            .frame(height: 100)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(
                material: themeManager.isRetroMode ? .windowBackground : .hudWindow,
                blendingMode: .behindWindow
            )
        )
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

// Добавим вспомогательное расширение для условного применения модификаторов
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

// Добавляем FirstLaunchView как внутреннюю структуру
private struct FirstLaunchView: View {
    @Binding var isPresented: Bool
    @StateObject private var themeManager = ThemeManager.shared
    @State private var isSuccess: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar with title
            HStack {
                Spacer()
                Text("Welcome to MIMP!")
                    .font(.system(
                        size: 13,
                        weight: .medium,
                        design: themeManager.isRetroMode ? .monospaced : .default
                    ))
                    .foregroundColor(Color.retroText)
                Spacer()
            }
            .frame(height: 28)
            
            // Main content
            HStack(spacing: 30) {
                // Column 1 - App Icon
                VStack(alignment: .center, spacing: 8) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(themeManager.isRetroMode ? 0 : 15)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    }
                }
                .frame(width: 120)

                // Column 2 - Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Would you like to set MIMP\nas the default player?")
                        .font(.system(
                            size: 11,
                            design: themeManager.isRetroMode ? .monospaced : .default
                        ))
                        .foregroundColor(Color.retroText.opacity(0.8))
                        .multilineTextAlignment(.leading)
                }
                .frame(width: 140, alignment: .leading)

                // Column 3 - Formats
                VStack(alignment: .leading, spacing: 8) {
                    Text(themeManager.isRetroMode ? 
                        "Formats: [\(AudioFormat.formatsDescription)]" :
                        "Formats: (\(AudioFormat.formatsDescription))")
                        .font(.system(
                            size: 11,
                            design: themeManager.isRetroMode ? .monospaced : .default
                        ))
                        .foregroundColor(Color.retroText.opacity(0.7))
                }
                .frame(width: 120)

                // Column 4 - Buttons and Status
                VStack(alignment: .trailing, spacing: 6) {
                    if isSuccess {
                        Text("✓ Set as Default")
                            .font(.system(
                                size: 11,
                                design: themeManager.isRetroMode ? .monospaced : .default
                            ))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.green)
                            )
                    } else {
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isPresented = false
                                    Settings.shared.isFirstLaunch = false
                                }
                            }) {
                                Text("Maybe Later")
                                    .font(.system(
                                        size: 11,
                                        design: themeManager.isRetroMode ? .monospaced : .default
                                    ))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.2))
                                    )
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

                            Button(action: {
                                setAsDefaultPlayer()
                                withAnimation {
                                    isSuccess = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isPresented = false
                                        Settings.shared.isFirstLaunch = false
                                    }
                                }
                            }) {
                                Text("Set as Default")
                                    .font(.system(
                                        size: 11,
                                        design: themeManager.isRetroMode ? .monospaced : .default
                                    ))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.blue)
                                    )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
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
                }
                .frame(width: 260)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity, minHeight: 128, idealHeight: 128, maxHeight: 128)
        .background(
            VisualEffectView(
                material: themeManager.isRetroMode ? .windowBackground : .hudWindow,
                blendingMode: .behindWindow
            )
        )
    }
    
    private func setAsDefaultPlayer() {
        let workspace = NSWorkspace.shared
        var successCount = 0
        var failedFormats: [String] = []
        
        // Регистрируем приложение для всех аудио файлов
        if let audioType = UTType("public.audio") {
            do {
                try workspace.setDefaultApplication(
                    at: Bundle.main.bundleURL,
                    toOpen: audioType
                )
            } catch {
                print("Failed to register for public.audio: \(error)")
            }
        }
        
        // Принудительная установка для проблемных форматов
        let forceTypes = [
            "aiff": [
                "public.aiff-audio",
                "public.aifc-audio",
                "com.apple.coreaudio-format",
                "public.audio",
                "com.apple.quicktime-movie"
            ],
            "m4a": [
                "public.mpeg-4-audio",
                "com.apple.m4a-audio",
                "public.audio",
                "com.apple.quicktime-movie",
                "public.mpeg-4"
            ]
        ]
        
        // Пробуем установить для каждого формата
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue) {
                do {
                    // Для проблемных форматов используем принудительную установку
                    if format.rawValue == "aiff" || format.rawValue == "m4a" {
                        // Регистрируем приложение
                        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
                        
                        // Устанавливаем для всех возможных типов
                        if let types = forceTypes[format.rawValue] {
                            for typeId in types {
                                LSSetDefaultRoleHandlerForContentType(
                                    typeId as CFString,
                                    LSRolesMask.all,
                                    Bundle.main.bundleIdentifier! as CFString
                                )
                                
                                if let forceType = UTType(typeId) {
                                    try? workspace.setDefaultApplication(
                                        at: Bundle.main.bundleURL,
                                        toOpen: forceType
                                    )
                                }
                            }
                        }
                    } else {
                        // Для остальных форматов используем стандартный подход
                        try workspace.setDefaultApplication(
                            at: Bundle.main.bundleURL,
                            toOpen: type
                        )
                    }
                    
                    // Проверяем результат
                    if let newHandler = LSCopyDefaultRoleHandlerForContentType(
                        type.identifier as CFString,
                        LSRolesMask.viewer
                    )?.takeRetainedValue() as String?,
                       newHandler == Bundle.main.bundleIdentifier {
                        successCount += 1
                    } else {
                        failedFormats.append(format.rawValue)
                    }
                } catch {
                    failedFormats.append(format.rawValue)
                }
            }
        }
        
        // Показываем успех, если хотя бы один формат установлен
        if successCount > 0 {
            isSuccess = true
        }
    }
}

#Preview {
    ContentView()
}
