import SwiftUI
import AppKit

private struct ChangelogSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

struct UpdateView: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var isCompactMode = Settings.shared.isCompactMode
    
    private func parseChangelog() -> [ChangelogSection] {
        guard let changelog = updateManager.changelog else { return [] }
        
        // Ищем строку с Release
        if let releaseRange = changelog.range(of: "Release") {
            // Берем все после Release
            let changes = changelog[releaseRange.upperBound...].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            var sections: [ChangelogSection] = []
            var currentTitle = ""
            var currentItems: [String] = []
            
            // Разбираем по строкам
            changes.components(separatedBy: CharacterSet.newlines).forEach { line in
                let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
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
    
    private func sectionView(_ section: ChangelogSection, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: isCompactMode ? 1 : 4) {
            Text(section.title)
                .font(.system(size: isCompactMode ? 11 : 12, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
                .frame(height: 16)
                .padding(.top, isCompactMode ? 6 : 10)
            
            ForEach(section.items, id: \.self) { item in
                Text("• " + item)
                    .font(.system(size: isCompactMode ? 10 : 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            HStack(spacing: 15) {
                let sections = parseChangelog()
                
                if sections.count > 0 {
                    // Left column
                    if let firstSection = sections.first {
                        sectionView(firstSection, alignment: .trailing)
                    }
                    
                    // Center column with version and buttons
                    VStack(spacing: 12) {
                        Text("What's New in \(updateManager.latestVersion ?? "")")
                            .font(.system(size: isCompactMode ? 12 : 13, weight: .medium))
                            .foregroundColor(.white)
                        
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
                                        .font(.system(size: isCompactMode ? 10 : 11))
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
                                        .font(.system(size: isCompactMode ? 10 : 11))
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
                    
                    // Right column
                    if sections.count > 1 {
                        sectionView(sections[1], alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isCompactMode ? 4 : 8)
        }
        .frame(
            minWidth: 600, 
            idealWidth: 800, 
            maxWidth: .infinity, 
            minHeight: isCompactMode ? 100 : 128,
            idealHeight: isCompactMode ? 100 : 128,
            maxHeight: isCompactMode ? 100 : 128
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCompactMode)
        .background(
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
        )
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isCompactMode = Settings.shared.isCompactMode
            }
        }
    }
} 