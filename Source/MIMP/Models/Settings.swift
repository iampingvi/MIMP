import Foundation

class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    
    private let volumeKey = "player.volume"
    private let lastVolumeKey = "player.lastVolume"
    private let isMutedKey = "player.isMuted"
    private let showRemainingTimeKey = "player.showRemainingTime"
    private let isFirstLaunchKey = "app.isFirstLaunch"
    private let autoUpdateEnabledKey = "app.autoUpdateEnabled"
    private let defaultPlayerSetKey = "app.defaultPlayerSet"
    
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
    
    var showRemainingTime: Bool {
        get { defaults.bool(forKey: showRemainingTimeKey) }
        set { defaults.set(newValue, forKey: showRemainingTimeKey) }
    }
    
    var isFirstLaunch: Bool {
        get { defaults.bool(forKey: isFirstLaunchKey) }
        set { defaults.set(newValue, forKey: isFirstLaunchKey) }
    }
    
    var autoUpdateEnabled: Bool {
        get { defaults.bool(forKey: autoUpdateEnabledKey) }
        set { defaults.set(newValue, forKey: autoUpdateEnabledKey) }
    }
    
    var isDefaultPlayerSet: Bool {
        get { defaults.bool(forKey: defaultPlayerSetKey) }
        set { defaults.set(newValue, forKey: defaultPlayerSetKey) }
    }
    
    private init() {
        // Временно раскомментируйте эту строку для тестирования:
//          defaults.removeObject(forKey: isFirstLaunchKey)
        
        if defaults.object(forKey: isFirstLaunchKey) == nil {
            defaults.set(true, forKey: isFirstLaunchKey)
        }
        if defaults.object(forKey: volumeKey) == nil {
            defaults.set(1.0, forKey: volumeKey)
        }
        if defaults.object(forKey: lastVolumeKey) == nil {
            defaults.set(1.0, forKey: lastVolumeKey)
        }
        if defaults.object(forKey: isMutedKey) == nil {
            defaults.set(false, forKey: isMutedKey)
        }
        if defaults.object(forKey: showRemainingTimeKey) == nil {
            defaults.set(false, forKey: showRemainingTimeKey)
        }
        if defaults.object(forKey: autoUpdateEnabledKey) == nil {
            defaults.set(true, forKey: autoUpdateEnabledKey)
        }
        if defaults.object(forKey: defaultPlayerSetKey) == nil {
            defaults.set(false, forKey: defaultPlayerSetKey)
        }
    }
} 
