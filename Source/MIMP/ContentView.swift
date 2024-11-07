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
    @State private var seekTimer: Timer?
    @State private var isSeekingForward = false
    @State private var isSeekingBackward = false
    @State private var showingFirstLaunch = Settings.shared.isFirstLaunch
    @StateObject private var updateManager = UpdateManager.shared
    @State private var pressedKeys: Set<String> = []
    @State private var lastKeyPressTime: Date = Date()
    @State private var isCompactMode = Settings.shared.isCompactMode

    var body: some View {
        ZStack(alignment: .top) {
            // Background blur
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
            .zIndex(1)

            // Background with artwork
            if let track = player.currentTrack, !showingAbout {
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
                    FirstLaunchView(isPresented: $showingFirstLaunch, isCompactMode: isCompactMode)
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                        .frame(height: isCompactMode ? 80 : 120)
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
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                // 1. Сначала проверяем комбинации с Command
                if event.modifierFlags.contains(.command) {
                    switch event.keyCode {
                    case 12: // Cmd+Q (quit)
                        NSApplication.shared.terminate(nil)
                        return nil
                    case 4:  // Cmd+H (hide)
                        NSApplication.shared.hide(nil)
                        return nil
                    default:
                        break
                    }
                }
                
                // 2. Затем проверяем обычные клавиши
                switch event.keyCode {
                case 49: // Space
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
                case 46: // M key (mute)
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] {
                        player.toggleMute()
                        return nil
                    }
                default:
                    // 3. Проверяем последовательность "deuse"
                    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
                    let currentTime = Date()
                    
                    if currentTime.timeIntervalSince(lastKeyPressTime) > 1.0 {
                        pressedKeys.removeAll()
                    }
                    lastKeyPressTime = currentTime
                    pressedKeys.insert(key)
                    
                    let sequence = "deuse"
                    if sequence.allSatisfy({ pressedKeys.contains(String($0)) }) {
                        resetDefaultPlayer()
                        pressedKeys.removeAll()
                        return nil
                    }
                }
                
                return event
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
            
            // Добавляем обработчик клавиатуры для сброса форматов
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
                let currentTime = Date()
                
                // Сбрасываем нажатые клавиши если прошло больше 1 секунды
                if currentTime.timeIntervalSince(lastKeyPressTime) > 1.0 {
                    pressedKeys.removeAll()
                }
                lastKeyPressTime = currentTime
                
                // Добавляем нажатую клавишу
                pressedKeys.insert(key)
                
                // Проверяем последоаельность "deuse"
                let sequence = "deuse"
                if sequence.allSatisfy({ pressedKeys.contains(String($0)) }) {
                    resetDefaultPlayer()
                    pressedKeys.removeAll()
                    return nil
                }
                
                return event
            }
            
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // First check for command shortcuts
                if event.modifierFlags.contains(.command) {
                    switch event.keyCode {
                    case 12: // Cmd+Q (quit)
                        NSApplication.shared.terminate(nil)
                        return nil
                    case 4:  // Cmd+H (hide)
                        NSApplication.shared.hide(nil)
                        return nil
                    case 46: // Cmd+M (minimize)
                        NSApp.mainWindow?.miniaturize(nil)
                        return nil
                    default:
                        break
                    }
                }
                
                // Then check for mute (M key without modifiers)
                if event.keyCode == 46 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] {
                    player.toggleMute()
                    return nil
                }
                
                return event
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
            // Показываем аудио информацию только если не в компактном режиме
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

// Переименовываем enum
enum PlayerDefaultStatus {
    case none           // Не установлен ни для одного формата
    case partial        // Установлен для некоторых фоматов
    case complete       // Установлен для всех форматов
}

struct AboutView: View {
    @Binding var showingAbout: Bool
    @State private var autoUpdateEnabled = Settings.shared.autoUpdateEnabled
    @State private var isDefaultPlayerSet = Settings.shared.isDefaultPlayerSet
    @StateObject private var updateManager = UpdateManager.shared
    @State private var isSuccess = false
    @State private var refreshTrigger = false
    @State private var isHeartHovered = false
    let isCompactMode: Bool
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MIMP"
    }

    private func checkDefaultPlayerStatus() -> Bool {
        // Проверяем все форматы
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue),
               let handler = LSCopyDefaultRoleHandlerForContentType(
                type.identifier as CFString,
                LSRolesMask.viewer
               )?.takeRetainedValue() as String? {
                // Если хотя бы один фомат не устанолен для нашего приложения
                if handler != Bundle.main.bundleIdentifier {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }

    private func getUnsetFormats() -> [String] {
        var unsetFormats: [String] = []
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue),
               let handler = LSCopyDefaultRoleHandlerForContentType(
                type.identifier as CFString,
                LSRolesMask.viewer
               )?.takeRetainedValue() as String? {
                if handler != Bundle.main.bundleIdentifier {
                    unsetFormats.append(format.rawValue.uppercased())
                }
            } else {
                unsetFormats.append(format.rawValue.uppercased())
            }
        }
        return unsetFormats
    }

    private func getDefaultPlayerStatus() -> PlayerDefaultStatus {
        let unsetFormats = getUnsetFormats()
        if unsetFormats.isEmpty {
            return .complete
        } else if unsetFormats.count == AudioFormat.allCases.count {
            return .none
        } else {
            return .partial
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCompactMode {
                // Компактный режим
                ZStack {
                    // Центральный контент
                    VStack(spacing: 4) {
                        // Заголовок с версией
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(appName)
                                .font(.system(size: 12, weight: .medium))
                            Text("(\(appVersion))")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.white)
                        
                        // Ссылки
                        HStack(spacing: 16) {
                            ForEach([
                                ("github-mark", "GitHub", "https://github.com/iampingvi/MIMP"),
                                ("cup.and.saucer.fill", "Support", "https://www.buymeacoffee.com/pingvi"),
                                ("globe", "Website", "https://mimp.pingvi.letz.dev")
                            ], id: \.1) { icon, text, urlString in
                                Link(destination: URL(string: urlString)!) {
                                    HStack(spacing: 4) {
                                        if icon == "github-mark" {
                                            Image(icon)
                                                .resizable()
                                                .frame(width: 12, height: 12)
                                                .colorMultiply(.white)
                                        } else {
                                            Image(systemName: icon)
                                                .font(.system(size: 12))
                                        }
                                        Text(text)
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .opacity(0.9)
                                .hover { hovering in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if let view = NSApp.keyWindow?.contentView?.hitTest(NSEvent.mouseLocation)?.enclosingScrollView {
                                            view.alphaValue = hovering ? 1 : 0.9
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Кнопка закрытя слева
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingAbout = false
                            }
                        }) {
                            Group {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 24)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 30)
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Футер с центрированным "Made with love"
                HStack {
                    DefaultPlayerStatusView(isCompactMode: isCompactMode)
                        .frame(maxWidth: .infinity)
                    
                    // Центральный элемент
                    HStack(spacing: 4) {
                        Text("Made with")
                            .font(.system(size: isCompactMode ? 10 : 11))
                        Image(systemName: "heart.fill")
                            .font(.system(size: isCompactMode ? 9 : 10))
                        Text("by PINGVI")
                            .font(.system(size: isCompactMode ? 10 : 11))
                    }
                    .foregroundColor(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    
                    // Правый элемент
                    HStack {
                        Button(action: {
                            autoUpdateEnabled.toggle()
                            Settings.shared.autoUpdateEnabled = autoUpdateEnabled
                            if autoUpdateEnabled {
                                Task {
                                    await updateManager.checkForUpdates(force: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: autoUpdateEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(autoUpdateEnabled ? .green : .white.opacity(0.7))
                                Text("Automatic Updates")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                
            } else {
                // Обычный режим
                ZStack {
                    // Центральный контент
                    HStack(spacing: 30) {
                        // Иконка приложения
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .cornerRadius(15)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Информация о прложении
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(appName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text("(\(appVersion))")
                                        .font(.system(size: 9))
                                }
                                Text("Minimal Interface Music Player")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.white)
                            
                            // Ссылки
                            HStack(spacing: 16) {
                                ForEach([
                                    ("github-mark", "GitHub", "https://github.com/iampingvi/MIMP"),
                                    ("cup.and.saucer.fill", "Support", "https://www.buymeacoffee.com/pingvi"),
                                    ("globe", "Website", "https://mimp.pingvi.letz.dev")
                                ], id: \.1) { icon, text, urlString in
                                    Link(destination: URL(string: urlString)!) {
                                        HStack(spacing: 6) {
                                            if icon == "github-mark" {
                                                Image(icon)
                                                    .resizable()
                                                    .frame(width: 14, height: 14)
                                                    .colorMultiply(.white)
                                            } else {
                                                Image(systemName: icon)
                                                    .font(.system(size: 12))
                                            }
                                            Text(text)
                                                .font(.system(size: 12))
                                        }
                                        .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(0.9)
                                    .hover { hovering in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if let view = NSApp.keyWindow?.contentView?.hitTest(NSEvent.mouseLocation)?.enclosingScrollView {
                                                view.alphaValue = hovering ? 1 : 0.9
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    
                    // Кнопка закрытия слева
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingAbout = false
                            }
                        }) {
                            Group {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 24)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 30)
                        Spacer()
                    }
                }
                .padding(.vertical, 12)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Футер с центрированным "Made with love"
                HStack {
                    DefaultPlayerStatusView(isCompactMode: isCompactMode)
                        .frame(maxWidth: .infinity)
                    
                    // Центральный элемент
                    HStack(spacing: 4) {
                        Text("Made with")
                            .font(.system(size: isCompactMode ? 10 : 11))
                        Image(systemName: "heart.fill")
                            .font(.system(size: isCompactMode ? 9 : 10))
                        Text("by PINGVI")
                            .font(.system(size: isCompactMode ? 10 : 11))
                    }
                    .foregroundColor(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    
                    // Правый элемент
                    HStack {
                        Button(action: {
                            autoUpdateEnabled.toggle()
                            Settings.shared.autoUpdateEnabled = autoUpdateEnabled
                            if autoUpdateEnabled {
                                Task {
                                    await updateManager.checkForUpdates(force: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: autoUpdateEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(autoUpdateEnabled ? .green : .white.opacity(0.7))
                                Text("Automatic Updates")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .frame(height: isCompactMode ? 80 : 120)
    }
}

// Переименовываем структуру
private struct DefaultPlayerStatusView: View {
    let isCompactMode: Bool
    @State private var isDefaultPlayerSet = Settings.shared.isDefaultPlayerSet
    @State private var refreshTrigger = false
    @State private var isSuccess = false
    
    var body: some View {
        HStack(spacing: 6) {
            switch getDefaultPlayerStatus() {
            case .none:
                Button(action: {
                    setAsDefaultPlayer()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: isCompactMode ? 10 : 11))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Set as default player")
                            .font(.system(size: isCompactMode ? 10 : 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                
            case .partial:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: isCompactMode ? 10 : 11))
                        .foregroundColor(.yellow)
                    let unsetFormats = getUnsetFormats()
                    Text("Not default for: \(unsetFormats.joined(separator: ", "))")
                        .font(.system(size: isCompactMode ? 10 : 11))
                    Button(action: {
                        setAsDefaultPlayer()
                    }) {
                        Text("Fix")
                            .font(.system(size: isCompactMode ? 10 : 11))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
            case .complete:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: isCompactMode ? 10 : 11))
                        .foregroundColor(.green)
                    Text("Set as default")
                        .font(.system(size: isCompactMode ? 10 : 11))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: getDefaultPlayerStatus())
        .animation(.easeInOut(duration: 0.2), value: refreshTrigger)
    }
    
    private func getDefaultPlayerStatus() -> PlayerDefaultStatus {
        let unsetFormats = getUnsetFormats()
        if unsetFormats.isEmpty {
            return .complete
        } else if unsetFormats.count == AudioFormat.allCases.count {
            return .none
        } else {
            return .partial
        }
    }
    
    private func getUnsetFormats() -> [String] {
        var unsetFormats: [String] = []
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue),
               let handler = LSCopyDefaultRoleHandlerForContentType(
                type.identifier as CFString,
                LSRolesMask.viewer
               )?.takeRetainedValue() as String? {
                if handler != Bundle.main.bundleIdentifier {
                    unsetFormats.append(format.rawValue.uppercased())
                }
            } else {
                unsetFormats.append(format.rawValue.uppercased())
            }
        }
        return unsetFormats
    }
    
    private func setAsDefaultPlayer() {
        let workspace = NSWorkspace.shared
        var successCount = 0
        var failedFormats: [String] = []
        
        print("\n=== MIMP Default Player Setup ===")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("App URL: \(Bundle.main.bundleURL.path)")
        
        // Register for all audio files
        if let audioType = UTType("public.audio") {
            workspace.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpen: audioType
            )
            print("✓ Registered for public.audio")
        }
        
        // Force settings for problematic formats
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
        
        // Try to set for each format
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue) {
                print("\nTrying to set default for .\(format.rawValue)")
                
                let currentHandler = LSCopyDefaultRoleHandlerForContentType(
                    type.identifier as CFString,
                    LSRolesMask.viewer
                )?.takeRetainedValue() as String?
                print("Current handler: \(currentHandler ?? "None")")
                
                var isSuccess = false
                
                if format.rawValue == "aiff" || format.rawValue == "m4a" {
                    print("Forcing default app for .\(format.rawValue)")
                    LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
                    
                    if let types = forceTypes[format.rawValue] {
                        for typeId in types {
                            let status = LSSetDefaultRoleHandlerForContentType(
                                typeId as CFString,
                                LSRolesMask.all,
                                Bundle.main.bundleIdentifier! as CFString
                            )
                            print("  Forced \(typeId): \(status == noErr ? "✓" : "✗")")
                            
                            if status != noErr, let forceType = UTType(typeId) {
                                workspace.setDefaultApplication(
                                    at: Bundle.main.bundleURL,
                                    toOpen: forceType
                                )
                                print("  Tried NSWorkspace for \(typeId)")
                            }
                            
                            if status == noErr {
                                isSuccess = true
                            }
                        }
                    }
                } else {
                    workspace.setDefaultApplication(
                        at: Bundle.main.bundleURL,
                        toOpen: type
                    )
                    isSuccess = true
                }
                
                if let newHandler = LSCopyDefaultRoleHandlerForContentType(
                    type.identifier as CFString,
                    LSRolesMask.viewer
                )?.takeRetainedValue() as String?,
                   newHandler == Bundle.main.bundleIdentifier || isSuccess {
                    successCount += 1
                    print("✓ Successfully set as default")
                    print("  New handler: \(newHandler)")
                } else {
                    failedFormats.append(format.rawValue)
                    print("✗ Handler not set")
                    print("  Current handler: \(currentHandler ?? "None")")
                }
            }
        }
        
        print("\n=== Summary ===")
        print("Total formats: \(AudioFormat.allCases.count)")
        print("Successfully set: \(successCount)")
        if !failedFormats.isEmpty {
            print("Failed formats: \(failedFormats.joined(separator: ", "))")
        }
        print("===============================\n")
        
        if successCount > 0 {
            isSuccess = true
            isDefaultPlayerSet = true
            refreshTrigger.toggle()
        }
    }
}

// В FooterContent меняем использование
private struct FooterContent: View {
    @Binding var autoUpdateEnabled: Bool
    @ObservedObject var updateManager: UpdateManager
    let isCompactMode: Bool
    
    var body: some View {
        HStack {
            // Чекбокс автообновлений
            Button(action: {
                autoUpdateEnabled.toggle()
                Settings.shared.autoUpdateEnabled = autoUpdateEnabled
                if autoUpdateEnabled {
                    Task {
                        await updateManager.checkForUpdates(force: true)
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: autoUpdateEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: isCompactMode ? 10 : 11))
                        .foregroundColor(autoUpdateEnabled ? .green : .white.opacity(0.7))
                    Text("Automatic Updates")
                        .font(.system(size: isCompactMode ? 10 : 11))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            DefaultPlayerStatusView(isCompactMode: isCompactMode)
        }
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

// Добавляем структуру FirstLaunchView
struct FirstLaunchView: View {
    @Binding var isPresented: Bool
    @State private var isSuccess = false
    let isCompactMode: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar with title
            HStack {
                Spacer()
                Text("Welcome to MIMP!")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(height: 28)
            
            // Main content
            HStack(spacing: isCompactMode ? 15 : 30) {
                // Column 1 - App Icon
                VStack(alignment: .center, spacing: 8) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: isCompactMode ? 48 : 64, height: isCompactMode ? 48 : 64)
                            .cornerRadius(15)
                    }
                }
                .frame(width: isCompactMode ? 80 : 120)

                // Column 2 - Description
                VStack(alignment: .leading, spacing: isCompactMode ? 4 : 6) {
                    Text("Would you like to set MIMP\nas the default player?")
                        .font(.system(size: isCompactMode ? 10 : 11))
                }
                .frame(width: isCompactMode ? 120 : 140, alignment: .leading)

                // Column 3 - Formats
                VStack(alignment: .leading, spacing: isCompactMode ? 6 : 8) {
                    Text("Formats: (\(AudioFormat.formatsDescription))")
                        .font(.system(size: isCompactMode ? 10 : 11))
                }
                .frame(width: isCompactMode ? 100 : 120)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity, minHeight: 128, idealHeight: 128, maxHeight: 128)
        .background(
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
        )
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

// Добавляем расширение для условного применения модификаторов
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
