import SwiftUI

struct UpdateView: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    private var formattedChangelog: String {
        guard let changelog = updateManager.changelog else { return "" }
        
        // Ищем последний ###
        if let range = changelog.range(of: "###", options: .backwards) {
            // Берем все после ###
            let changes = changelog[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return changes
        }
        
        return changelog
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Spacer()
            Text("What's New in \(updateManager.latestVersion ?? "")")
                    .font(.system(
                        size: 13,
                        weight: .medium,
                        design: themeManager.isRetroMode ? .monospaced : .default
                    ))
                    .foregroundColor(Color.retroText)
                Spacer()
            }
            .frame(height: 28)
            
  
            
            // Main content
            HStack(spacing: 15) {
                // Version info и Changelog
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(formattedChangelog)
                            .font(.system(
                                size: 11,
                                design: themeManager.isRetroMode ? .monospaced : .default
                            ))
                            .foregroundColor(Color.retroText.opacity(0.7))
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 60)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 15)
                
                // Buttons (всегда справа)
                VStack(alignment: .trailing, spacing: 6) {
                    if updateManager.downloadProgress > 0 {
                        ProgressView(value: updateManager.downloadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 100)
                    } else {
                        HStack(spacing: 8) {
                            Button(action: {
                                updateManager.showingUpdate = false
                            }) {
                                Text("Skip")
                                    .font(.system(
                                        size: 11,
                                        design: themeManager.isRetroMode ? .monospaced : .default
                                    ))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.2))
                                    )
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                Task {
                                    try? await updateManager.downloadAndInstallUpdate()
                                }
                            }) {
                                Text("Update")
                                    .font(.system(
                                        size: 11,
                                        design: themeManager.isRetroMode ? .monospaced : .default
                                    ))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.blue)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 160)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity, minHeight: 128, idealHeight: 128, maxHeight: 128)
        .background(
            VisualEffectView(
                material: themeManager.isRetroMode ? .windowBackground : .hudWindow,
                blendingMode: .behindWindow
            )
        )
    }
} 