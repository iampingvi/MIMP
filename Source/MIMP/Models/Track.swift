import Foundation

struct Track: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let duration: TimeInterval
    let bpm: Double
    let key: String
    let artwork: URL?
    let fileURL: URL
    var waveformData: [Float]?
    var tags: [String]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
} 