import Foundation

enum AudioFormat: String, CaseIterable {
    case mp3 = "mp3"
    case aiff = "aiff"
    case flac = "flac"
    case wav = "wav"
    case m4a = "m4a"
    
    static var allExtensions: [String] {
        Self.allCases.map { $0.rawValue }
    }
    
    static var formatsDescription: String {
        allExtensions.map { $0.uppercased() }.joined(separator: ", ")
    }
} 