import SwiftUI

struct TrackInfoView: View {
    let track: Track
    
    var body: some View {
        HStack {
            // Cover art
            if let artworkURL = track.artwork {
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
                Text(track.title)
                    .font(.headline)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
} 