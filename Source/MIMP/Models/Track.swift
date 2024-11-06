import Foundation
import SwiftUI

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
    
    @ViewBuilder
    func infoView() -> some View {
        HStack {
            // Cover art
            if let artworkURL = artwork {
                AsyncImage(url: artworkURL) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                    )
            }
            
            // Track info
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    func metadataView() -> some View {
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