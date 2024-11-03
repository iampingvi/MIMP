import Foundation

class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    
    private let volumeKey = "player.volume"
    private let lastVolumeKey = "player.lastVolume"
    private let isMutedKey = "player.isMuted"
    
    var volume: Float {
        get { Float(defaults.double(forKey: volumeKey)) }
        set { defaults.set(Double(newValue), forKey: volumeKey) }
    }
    
    var lastVolume: Float {
        get { Float(defaults.double(forKey: lastVolumeKey)) }
        set { defaults.set(Double(newValue), forKey: lastVolumeKey) }
    }
    
    var isMuted: Bool {
        get { defaults.bool(forKey: isMutedKey) }
        set { defaults.set(newValue, forKey: isMutedKey) }
    }
    
    private init() {
        if defaults.object(forKey: volumeKey) == nil {
            defaults.set(1.0, forKey: volumeKey)
        }
        if defaults.object(forKey: lastVolumeKey) == nil {
            defaults.set(1.0, forKey: lastVolumeKey)
        }
        if defaults.object(forKey: isMutedKey) == nil {
            defaults.set(false, forKey: isMutedKey)
        }
    }
} 