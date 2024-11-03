import SwiftUI

struct TrackMetadataView: View {
    let bpm: Double
    let key: String
    
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "metronome")
                    .symbolEffect(.bounce, options: .repeating)
                Text("\(Int(bpm)) BPM")
            }
            
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .symbolEffect(.pulse)
                Text(key)
            }
        }
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
} 