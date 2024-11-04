import SwiftUI

private struct ChangelogSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

struct UpdateView: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    private func parseChangelog() -> [ChangelogSection] {
        guard let changelog = updateManager.changelog else { return [] }
        
        // Ищем строку с Release
        if let releaseRange = changelog.range(of: "Release") {
            // Берем все после Release
            let changes = changelog[releaseRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            
            var sections: [ChangelogSection] = []
            var currentTitle = ""
            var currentItems: [String] = []
            
            // Разбираем по строкам
            changes.components(separatedBy: .newlines).forEach { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("###") {
                    // Сохраняем предыдущую секцию
                    if !currentTitle.isEmpty && !currentItems.isEmpty {
                        sections.append(ChangelogSection(title: currentTitle, items: currentItems))
                    }
                    // Начинаем новую секцию
                    currentTitle = trimmed.replacingOccurrences(of: "### ", with: "")
                    currentItems = []
                } else if trimmed.hasPrefix("-") {
                    let item = trimmed.replacingOccurrences(of: "- ", with: "")
                    currentItems.append(item)
                }
            }
            
            // Добавляем последнюю секцию
            if !currentTitle.isEmpty && !currentItems.isEmpty {
                sections.append(ChangelogSection(title: currentTitle, items: currentItems))
            }
            
            return sections
        }
        return []
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
                // Changelog content
                let sections = parseChangelog()
                
                HStack(alignment: .top, spacing: 20) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .font(.system(
                                    size: 12,
                                    weight: .bold,
                                    design: themeManager.isRetroMode ? .monospaced : .default
                                ))
                                .foregroundColor(Color.retroText)
                            
                            ForEach(section.items, id: \.self) { item in
                                Text("• " + item)
                                    .font(.system(
                                        size: 11,
                                        design: themeManager.isRetroMode ? .monospaced : .default
                                    ))
                                    .foregroundColor(Color.retroText.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 15)
                .transition(.move(edge: .top).combined(with: .opacity))
                
                // Buttons
                VStack(alignment: .trailing, spacing: 6) {
                    if updateManager.downloadProgress > 0 {
                        ProgressView(value: updateManager.downloadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 100)
                    } else {
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    updateManager.showingUpdate = false
                                }
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
        .transition(.move(edge: .top))
    }
} 