struct AudioInfo {
    let format: String
    let bitRate: Int
    
    var description: String {
        "\(format) | \(bitRate) kbps"
    }
} 