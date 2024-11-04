struct AudioInfo {
    let format: String
    let bitRate: Int
    let sampleRate: Int
    let channels: Int
    
    var description: String {
        "\(format) | \(bitRate) kbps | \(sampleRateDescription) | \(channelsDescription)"
    }
    
    var sampleRateDescription: String {
        let kHz = Double(sampleRate) / 1000.0
        return String(format: "%.1f kHz", kHz)
    }
    
    var channelsDescription: String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(channels) channels"
        }
    }
} 