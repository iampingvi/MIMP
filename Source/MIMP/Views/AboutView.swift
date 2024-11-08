import SwiftUI
import UniformTypeIdentifiers // Добавляем импорт для UTType
import CoreServices // Добавляем импорт для LSCopyDefaultRoleHandlerForContentType и других LS* функций
import AppKit // Добавляем импорт для NSWorkspace

struct AboutView: View {
    @Binding var showingAbout: Bool
    @State private var autoUpdateEnabled = Settings.shared.autoUpdateEnabled
    @State private var isDefaultPlayerSet = Settings.shared.isDefaultPlayerSet
    @StateObject private var updateManager = UpdateManager.shared
    @State private var isSuccess = false
    @State private var refreshTrigger = false
    @State private var isHeartHovered = false
    let isCompactMode: Bool
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MIMP"
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCompactMode {
                // Компактный режим
                ZStack {
                    // Центральный контент
                    VStack(spacing: 4) {
                        // Заголовок с версией
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(appName)
                                .font(.system(size: 12, weight: .medium))
                            Text("(\(appVersion))")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.white)
                        
                        // Ссылки
                        HStack(spacing: 16) {
                            ForEach([
                                ("github-mark", "GitHub", "https://github.com/iampingvi/MIMP"),
                                ("cup.and.saucer.fill", "Support", "https://www.buymeacoffee.com/pingvi"),
                                ("globe", "Website", "https://mimp.pingvi.letz.dev")
                            ], id: \.1) { icon, text, urlString in
                                Link(destination: URL(string: urlString)!) {
                                    HStack(spacing: 4) {
                                        if icon == "github-mark" {
                                            Image(icon)
                                                .resizable()
                                                .frame(width: 12, height: 12)
                                                .colorMultiply(.white)
                                        } else {
                                            Image(systemName: icon)
                                                .font(.system(size: 12))
                                        }
                                        Text(text)
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .opacity(0.9)
                                .hover { hovering in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if let view = NSApp.keyWindow?.contentView?.hitTest(NSEvent.mouseLocation)?.enclosingScrollView {
                                            view.alphaValue = hovering ? 1 : 0.9
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Кнопка закрытя слева
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingAbout = false
                            }
                        }) {
                            Group {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 24)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 30)
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Футер с центрированным "Made with love"
                HStack {
                    DefaultPlayerStatusView(isCompactMode: isCompactMode)
                        .frame(maxWidth: .infinity)
                    
                    // Центральный элемент
                    HStack(spacing: 4) {
                        Text("Made with")
                            .font(.system(size: isCompactMode ? 10 : 11))
                        Image(systemName: "heart.fill")
                            .font(.system(size: isCompactMode ? 9 : 10))
                        Text("by PINGVI")
                            .font(.system(size: isCompactMode ? 10 : 11))
                    }
                    .foregroundColor(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    
                    // Правый элемент
                    HStack {
                        Button(action: {
                            autoUpdateEnabled.toggle()
                            Settings.shared.autoUpdateEnabled = autoUpdateEnabled
                            if autoUpdateEnabled {
                                Task {
                                    await updateManager.checkForUpdates(force: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: autoUpdateEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(autoUpdateEnabled ? .green : .white.opacity(0.7))
                                Text("Automatic Updates")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                
            } else {
                // Обычный режим
                ZStack {
                    // Центральный контент
                    HStack(spacing: 30) {
                        // Иконка приложения
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .cornerRadius(15)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Информация о прложении
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(appName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text("(\(appVersion))")
                                        .font(.system(size: 9))
                                }
                                Text("Minimal Interface Music Player")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.white)
                            
                            // Ссылки
                            HStack(spacing: 16) {
                                ForEach([
                                    ("github-mark", "GitHub", "https://github.com/iampingvi/MIMP"),
                                    ("cup.and.saucer.fill", "Support", "https://www.buymeacoffee.com/pingvi"),
                                    ("globe", "Website", "https://mimp.pingvi.letz.dev")
                                ], id: \.1) { icon, text, urlString in
                                    Link(destination: URL(string: urlString)!) {
                                        HStack(spacing: 6) {
                                            if icon == "github-mark" {
                                                Image(icon)
                                                    .resizable()
                                                    .frame(width: 14, height: 14)
                                                    .colorMultiply(.white)
                                            } else {
                                                Image(systemName: icon)
                                                    .font(.system(size: 12))
                                            }
                                            Text(text)
                                                .font(.system(size: 12))
                                        }
                                        .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(0.9)
                                    .hover { hovering in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if let view = NSApp.keyWindow?.contentView?.hitTest(NSEvent.mouseLocation)?.enclosingScrollView {
                                                view.alphaValue = hovering ? 1 : 0.9
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    
                    // Кнопка закрытия слева
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingAbout = false
                            }
                        }) {
                            Group {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 24)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 30)
                        Spacer()
                    }
                }
                .padding(.vertical, 12)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Футер с центрированным "Made with love"
                HStack {
                    DefaultPlayerStatusView(isCompactMode: isCompactMode)
                        .frame(maxWidth: .infinity)
                    
                    // Центральный элемент
                    HStack(spacing: 4) {
                        Text("Made with")
                            .font(.system(size: isCompactMode ? 10 : 11))
                        Image(systemName: "heart.fill")
                            .font(.system(size: isCompactMode ? 9 : 10))
                        Text("by PINGVI")
                            .font(.system(size: isCompactMode ? 10 : 11))
                    }
                    .foregroundColor(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    
                    // Правый элемент
                    HStack {
                        Button(action: {
                            autoUpdateEnabled.toggle()
                            Settings.shared.autoUpdateEnabled = autoUpdateEnabled
                            if autoUpdateEnabled {
                                Task {
                                    await updateManager.checkForUpdates(force: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: autoUpdateEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(autoUpdateEnabled ? .green : .white.opacity(0.7))
                                Text("Automatic Updates")
                                    .font(.system(size: isCompactMode ? 10 : 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .frame(height: isCompactMode ? 80 : 120)
    }
}

// Вспомогательные структуры
private struct DefaultPlayerStatusView: View {
    let isCompactMode: Bool
    @State private var isDefaultPlayerSet = Settings.shared.isDefaultPlayerSet
    @State private var refreshTrigger = false
    @State private var isSuccess = false
    @State private var isSettingDefault = false // Добавляем состояние для отслеживания процесса
    
    var body: some View {
        HStack(spacing: 6) {
            if isSettingDefault {
                // Показываем индикатор загрузки во время установки
                ProgressView()
                    .scaleEffect(0.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text("Setting default...")
                    .font(.system(size: isCompactMode ? 10 : 11))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                switch getDefaultPlayerStatus() {
                case .none:
                    Button(action: {
                        Task {
                            isSettingDefault = true
                            await setAsDefaultPlayer()
                            isSettingDefault = false
                            refreshTrigger.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.system(size: isCompactMode ? 10 : 11))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Set as default player")
                                .font(.system(size: isCompactMode ? 10 : 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSettingDefault)
                    
                case .partial:
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: isCompactMode ? 10 : 11))
                            .foregroundColor(.yellow)
                        let unsetFormats = getUnsetFormats()
                        Text("Not default for: \(unsetFormats.joined(separator: ", "))")
                            .font(.system(size: isCompactMode ? 10 : 11))
                        Button(action: {
                            Task {
                                isSettingDefault = true
                                await setAsDefaultPlayer()
                                isSettingDefault = false
                                refreshTrigger.toggle()
                            }
                        }) {
                            Text("Fix")
                                .font(.system(size: isCompactMode ? 10 : 11))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.blue, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSettingDefault)
                    }
                    
                case .complete:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: isCompactMode ? 10 : 11))
                            .foregroundColor(.green)
                        Text("Set as default")
                            .font(.system(size: isCompactMode ? 10 : 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: getDefaultPlayerStatus())
        .animation(.easeInOut(duration: 0.2), value: refreshTrigger)
        .animation(.easeInOut(duration: 0.2), value: isSettingDefault)
    }
    
    private func getDefaultPlayerStatus() -> PlayerDefaultStatus {
        let unsetFormats = getUnsetFormats()
        if unsetFormats.isEmpty {
            return .complete
        } else if unsetFormats.count == AudioFormat.allCases.count {
            return .none
        } else {
            return .partial
        }
    }
    
    private func getUnsetFormats() -> [String] {
        var unsetFormats: [String] = []
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue),
               let handler = LSCopyDefaultRoleHandlerForContentType(
                type.identifier as CFString,
                LSRolesMask.viewer
               )?.takeRetainedValue() as String? {
                if handler != Bundle.main.bundleIdentifier {
                    unsetFormats.append(format.rawValue.uppercased())
                }
            } else {
                unsetFormats.append(format.rawValue.uppercased())
            }
        }
        return unsetFormats
    }
    
    private func setAsDefaultPlayer() {
        let workspace = NSWorkspace.shared
        var successCount = 0
        var failedFormats: [String] = []
        
        print("\n=== MIMP Default Player Setup ===")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("App URL: \(Bundle.main.bundleURL.path)")
        
        // Register for all audio files
        if let audioType = UTType("public.audio") {
            workspace.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpen: audioType
            )
            print("✓ Registered for public.audio")
        }
        
        // Force settings for problematic formats
        let forceTypes = [
            "aiff": [
                "public.aiff-audio",
                "public.aifc-audio",
                "com.apple.coreaudio-format",
                "public.audio",
                "com.apple.quicktime-movie"
            ],
            "m4a": [
                "public.mpeg-4-audio",
                "com.apple.m4a-audio",
                "public.audio",
                "com.apple.quicktime-movie",
                "public.mpeg-4"
            ]
        ]
        
        // Try to set for each format
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue) {
                print("\nTrying to set default for .\(format.rawValue)")
                
                let currentHandler = LSCopyDefaultRoleHandlerForContentType(
                    type.identifier as CFString,
                    LSRolesMask.viewer
                )?.takeRetainedValue() as String?
                print("Current handler: \(currentHandler ?? "None")")
                
                var isSuccess = false
                
                if format.rawValue == "aiff" || format.rawValue == "m4a" {
                    print("Forcing default app for .\(format.rawValue)")
                    LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
                    
                    if let types = forceTypes[format.rawValue] {
                        for typeId in types {
                            let status = LSSetDefaultRoleHandlerForContentType(
                                typeId as CFString,
                                LSRolesMask.all,
                                Bundle.main.bundleIdentifier! as CFString
                            )
                            print("  Forced \(typeId): \(status == noErr ? "✓" : "✗")")
                            
                            if status != noErr, let forceType = UTType(typeId) {
                                workspace.setDefaultApplication(
                                    at: Bundle.main.bundleURL,
                                    toOpen: forceType
                                )
                                print("  Tried NSWorkspace for \(typeId)")
                            }
                            
                            if status == noErr {
                                isSuccess = true
                            }
                        }
                    }
                } else {
                    workspace.setDefaultApplication(
                        at: Bundle.main.bundleURL,
                        toOpen: type
                    )
                    isSuccess = true
                }
                
                if let newHandler = LSCopyDefaultRoleHandlerForContentType(
                    type.identifier as CFString,
                    LSRolesMask.viewer
                )?.takeRetainedValue() as String?,
                   newHandler == Bundle.main.bundleIdentifier || isSuccess {
                    successCount += 1
                    print("✓ Successfully set as default")
                    print("  New handler: \(newHandler)")
                } else {
                    failedFormats.append(format.rawValue)
                    print("✗ Handler not set")
                    print("  Current handler: \(currentHandler ?? "None")")
                }
            }
        }
        
        print("\n=== Summary ===")
        print("Total formats: \(AudioFormat.allCases.count)")
        print("Successfully set: \(successCount)")
        if !failedFormats.isEmpty {
            print("Failed formats: \(failedFormats.joined(separator: ", "))")
        }
        print("===============================\n")
        
        if successCount > 0 {
            isSuccess = true
            Settings.shared.isDefaultPlayerSet = true
        }
    }
}

enum PlayerDefaultStatus {
    case none           // Не установлен ни для одного формата
    case partial        // Установлен для некоторых фоматов
    case complete       // Установлен для всех форматов
} 