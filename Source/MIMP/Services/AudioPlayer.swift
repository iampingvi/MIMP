import AVFoundation
import Combine
import AppKit
import MediaPlayer

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    private var player: AVAudioPlayer?
    private let analyzer = AudioAnalyzer()
    private var keyMonitor: Any?
    private var audioEngine: AVAudioEngine?

    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isAnalyzing: Bool = false

    @Published private(set) var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
            if !isMuted {
                Settings.shared.volume = volume
            }
        }
    }
    @Published private(set) var isMuted: Bool = false
    private var lastVolume: Float = 1.0

    @Published private(set) var audioInfo: AudioInfo?

    private var timer: Timer?
    private var analysisTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var cleanupFlag = false

    init() {
        let settings = Settings.shared
        self.isMuted = settings.isMuted
        self.lastVolume = settings.lastVolume
        self.volume = settings.isMuted ? 0 : settings.volume

        setupAudioSession()
        setupRemoteCommandCenter()
        
        // Store the cancellable in a local variable first
        let terminationCancellable = NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.cleanupResources()
                }
            }
        
        // Then store it in the set
        cancellables.insert(terminationCancellable)
    }

    deinit {
        // Create local copies of properties that need cleanup
        let monitor = keyMonitor
        let engine = audioEngine
        let currentAnalysisTask = analysisTask
        let currentTimer = timer
        
        // Cancel tasks
        currentAnalysisTask?.cancel()
        currentTimer?.invalidate()
        
        // Stop audio
        engine?.stop()
        player?.stop()
        
        // Remove monitor
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func cleanupResources() {
        guard !cleanupFlag else { return }
        cleanupFlag = true

        // Cancel any async tasks
        analysisTask?.cancel()
        analysisTask = nil
        stopTimer()

        // Remove notification observer
        cancellables.removeAll()

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        audioEngine?.stop()
        audioEngine = nil

        player?.stop()
        player = nil

        currentTime = 0
        isPlaying = false
        currentTrack = nil
        isAnalyzing = false
    }

    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event -> NSEvent? in
            if event.keyCode == 49 { // Space key
                self?.togglePlayPause()
                return nil
            }
            return event
        }
    }

    private func setupAudioSession() {
        audioEngine = AVAudioEngine()
    }

    private func setupRemoteCommandCenter() {
        // Configure the media remote command center
        let commandCenter = MPRemoteCommandCenter.shared()

        // Clear previous handlers
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        // Add new handlers
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        // Add seek handler
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in
                self.seek(to: positionEvent.positionTime)
                self.updateNowPlaying() // Update information after seeking
            }
            return .success
        }

        // Enable seek commands
        commandCenter.changePlaybackPositionCommand.isEnabled = true
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Add parameters for seeking
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        nowPlayingInfo[MPNowPlayingInfoPropertyCurrentPlaybackDate] = Date()

        // Add artwork if available
        if let artworkURL = track.artwork,
           let artworkImage = NSImage(contentsOf: artworkURL) {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { size in
                return artworkImage
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
        updateNowPlaying()
    }

    func load(url: URL) async throws {
        // First, load all data
        let asset = AVURLAsset(url: url)
        let metadata = try await loadMetadata(from: asset)
        let artwork = try await loadArtwork(from: asset)
        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.volume = volume
        audioPlayer.prepareToPlay()

        // Then update the UI
        cleanupResources()
        cleanupFlag = false

        self.player = audioPlayer
        self.currentTrack = Track(
            title: metadata.title ?? url.deletingPathExtension().lastPathComponent,
            artist: metadata.artist ?? "Unknown Artist",
            duration: audioPlayer.duration,
            bpm: 0,
            key: "-",
            artwork: artwork,
            fileURL: url,
            waveformData: [],
            tags: metadata.tags
        )

        // Start background analysis after setting the track
        startBackgroundAnalysis(url: url)

        // Start playback
        play()

        // Update Now Playing
        updateNowPlaying()

        // Get audio format info
        let format = url.pathExtension.uppercased()
        
        // Get bitrate using AVAsset
        let bitRate: Int
        if let track = try? await asset.load(.tracks).first {
            let estimatedDataRate = try? await track.load(.estimatedDataRate)
            if let dataRate = estimatedDataRate, dataRate > 0 {
                // Округляем до ближайшего стандартного битрейта
                let standardBitrates: [Int]
                switch format.lowercased() {
                case "flac", "wav":
                    standardBitrates = [320, 470, 940, 1411, 2116, 2823, 3529, 4233]  // Добавляем битрейты для FLAC/WAV
                default:
                    standardBitrates = [32, 64, 96, 128, 160, 192, 224, 256, 320]  // Стандартные битрейты для MP3/AAC
                }
                let normalizedBitRate = Int(round(dataRate / 1000))
                bitRate = standardBitrates.min(by: { abs($0 - normalizedBitRate) < abs($1 - normalizedBitRate) }) ?? normalizedBitRate
            } else {
                // Fallback to approximate calculation
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                let duration = audioPlayer.duration
                
                // Вычитаем размер обложки, если она есть
                var adjustedFileSize = fileSize
                if let artworkData = try? await loadArtworkData(from: asset) {
                    adjustedFileSize -= artworkData.count
                }
                
                // Вычисляем и округляем до ближайшего стандартного битрейта
                let calculatedBitRate = duration > 0 ? Int(Double(adjustedFileSize * 8) / duration / 1000) : 0
                let standardBitrates: [Int]
                switch format.lowercased() {
                case "flac", "wav":
                    standardBitrates = [320, 470, 940, 1411, 2116, 2823, 3529, 4233]
                default:
                    standardBitrates = [32, 64, 96, 128, 160, 192, 224, 256, 320]
                }
                bitRate = standardBitrates.min(by: { abs($0 - calculatedBitRate) < abs($1 - calculatedBitRate) }) ?? calculatedBitRate
            }
        } else {
            bitRate = 0
        }
        
        let sampleRate = Int(audioPlayer.format.sampleRate)
        let channels = audioPlayer.format.channelCount

        self.audioInfo = AudioInfo(
            format: format,
            bitRate: bitRate,
            sampleRate: sampleRate,
            channels: Int(channels)
        )
    }

    private func loadMetadata(from asset: AVURLAsset) async throws -> AudioMetadata {
        let commonMetadata = try await asset.loadMetadata()
        var title: String?
        var artist: String?
        var tags: [String] = []

        for item in commonMetadata {
            if let key = item.commonKey {
                switch key {
                case .commonKeyTitle:
                    title = await item.stringValue
                case .commonKeyArtist:
                    artist = await item.stringValue
                default:
                    if let value = await item.stringValue {
                        tags.append(value)
                    }
                }
            }
        }

        return AudioMetadata(title: title, artist: artist, artwork: nil, tags: tags)
    }

    private func loadArtwork(from asset: AVURLAsset) async throws -> URL? {
        let metadata = try await asset.loadMetadata()
        
        for item in metadata {
            if item.commonKey == .commonKeyArtwork,
               let data = await item.dataValue {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".jpg")
                try data.write(to: tempURL)
                return tempURL
            }
        }
        
        return nil
    }

    private func startBackgroundAnalysis(url: URL) {
        analysisTask?.cancel()
        analysisTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let analysis = try await self.analyzer.analyzeAudio(url: url)
                guard let track = self.currentTrack else { return }
                self.currentTrack = Track(
                    title: track.title,
                    artist: track.artist,
                    duration: track.duration,
                    bpm: analysis.bpm,
                    key: analysis.key,
                    artwork: track.artwork,
                    fileURL: track.fileURL,
                    waveformData: analysis.waveform,
                    tags: track.tags
                )
            } catch {
                print("Analysis error:", error)
            }
        }
    }

    func play() {
        player?.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time

        // If the track was seeked, start playback
        if !isPlaying {
            play()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let player = self.player else { return }
                self.currentTime = player.currentTime
                self.updateNowPlaying() // Update playback time information
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func toggleMute() {
        if isMuted {
            // Restore previous volume
            volume = lastVolume
            isMuted = false
        } else {
            // Save current volume and set to 0
            lastVolume = volume
            Settings.shared.lastVolume = lastVolume
            volume = 0
            isMuted = true
        }
        Settings.shared.isMuted = isMuted
        player?.volume = volume
    }

    func setVolume(_ newVolume: Float) {
        let normalizedVolume = max(0, min(1, newVolume))
        volume = normalizedVolume
        player?.volume = normalizedVolume

        if normalizedVolume > 0 {
            isMuted = false
            Settings.shared.isMuted = false
            lastVolume = normalizedVolume
            Settings.shared.lastVolume = lastVolume
            Settings.shared.volume = normalizedVolume
        } else if normalizedVolume == 0 && !isMuted {
            isMuted = true
            Settings.shared.isMuted = true
            Settings.shared.volume = 0
        }
    }

    // Add new methods for seeking and volume control with steps
    func seekRelative(_ offset: TimeInterval) {
        guard let player = player,
              let track = currentTrack else { return }
        
        let newTime = max(0, min(track.duration, currentTime + offset))
        seek(to: newTime)
    }
    
    func adjustVolume(by delta: Float) {
        let newVolume = max(0, min(1, volume + delta))
        setVolume(newVolume)
    }

    // Добавим новый вспомогательный метод для получения данных обложки
    private func loadArtworkData(from asset: AVURLAsset) async throws -> Data? {
        let metadata = try await asset.loadMetadata()
        
        for item in metadata {
            if item.commonKey == .commonKeyArtwork {
                return await item.dataValue
            }
        }
        
        return nil
    }
}

struct AudioMetadata: Sendable {
    let title: String?
    let artist: String?
    let artwork: URL?
    let tags: [String]
}

enum AudioPlayerError: Error {
    case unsupportedFormat
    case failedToLoad(Error)
}

// Helper extension for AVURLAsset
extension AVURLAsset {
    func loadMetadata() async throws -> [AVMetadataItem] {
        try await self.load(.commonMetadata)
    }
}

// Helper extension for AVMetadataItem
extension AVMetadataItem {
    var stringValue: String? {
        get async {
            try? await self.load(.stringValue)
        }
    }
    
    var dataValue: Data? {
        get async {
            try? await self.load(.dataValue)
        }
    }
}
