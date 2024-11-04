import SwiftUI

struct TrackMetadataView: View {
    let bpm: Double
    let key: String
    
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "metronome")
                Text("\(Int(bpm)) BPM")
            }
            
            HStack(spacing: 8) {
                Image(systemName: "music.note")
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