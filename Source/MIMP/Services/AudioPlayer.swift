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
    }

    deinit {
        Task { @MainActor in
            cleanupResources()
        }
    }

    private func cleanupResources() {
        guard !cleanupFlag else { return }
        cleanupFlag = true

        analysisTask?.cancel()
        analysisTask = nil
        stopTimer()

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        audioEngine?.stop()
        audioEngine = nil

        player?.stop()
        player = nil

        cancellables.removeAll()

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
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = volume
        player.prepareToPlay()

        // Then update the UI
        await cleanupResources()
        cleanupFlag = false

        self.player = player
        self.currentTrack = Track(
            title: metadata.title ?? url.deletingPathExtension().lastPathComponent,
            artist: metadata.artist ?? "Unknown Artist",
            duration: player.duration,
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
    }

    private func loadMetadata(from asset: AVURLAsset) async throws -> AudioMetadata {
        let commonMetadata = try await asset.load(.commonMetadata)
        var title: String?
        var artist: String?
        var tags: [String] = []

        for item in commonMetadata {
            let key = try await item.commonKey
            if let key = key {
                switch key {
                case .commonKeyTitle:
                    title = try await item.load(.stringValue)
                case .commonKeyArtist:
                    artist = try await item.load(.stringValue)
                default:
                    if let value = try await item.load(.stringValue) {
                        tags.append(value)
                    }
                }
            }
        }

        return AudioMetadata(title: title, artist: artist, artwork: nil, tags: tags)
    }

    private func loadArtwork(from asset: AVURLAsset) async throws -> URL? {
        let metadata = try await asset.load(.commonMetadata)
        
        for item in metadata {
            let key = try await item.commonKey
            if key == .commonKeyArtwork {
                let data = try await item.load(.dataValue)
                if let data = data {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".jpg")
                    try data.write(to: tempURL)
                    return tempURL
                }
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
}

struct AudioMetadata {
    let title: String?
    let artist: String?
    let artwork: URL?
    let tags: [String]
}

enum AudioPlayerError: Error {
    case unsupportedFormat
    case failedToLoad(Error)
}
