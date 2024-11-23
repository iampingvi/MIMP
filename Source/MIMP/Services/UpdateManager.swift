import Foundation
import SwiftUI

@MainActor
class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()
    
    @Published var isUpdateAvailable = false {
        didSet {
            if !isUpdateAvailable {
                showingUpdate = false
            }
        }
    }
    @Published var showingUpdate = false
    @Published var latestVersion: String?
    @Published var changelog: String?
    @Published var isChecking = false
    @Published var downloadProgress: Double = 0
    
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    
    private override init() {
        super.init()
        Task {
            await checkForUpdates()
        }
    }
    
    func checkForUpdates(force: Bool = false) async {
        // Проверяем настройку автообновления только если это не принудительная проверка
        if !force {
            guard Settings.shared.autoUpdateEnabled else { return }
        }
        
        guard !isChecking else { return }
        isChecking = true
        
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/iampingvi/MIMP/releases/latest")!)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("MIMP/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                isChecking = false
                return
            }
            
            print("GitHub API Response Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 403 {
                print("Rate limit exceeded")
                isChecking = false
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                print("Unexpected status code: \(httpResponse.statusCode)")
                isChecking = false
                return
            }
            
            let release = try JSONDecoder().decode(GithubRelease.self, from: data)
            print("Latest version from GitHub: \(release.tagName)")
            print("Current version: \(currentVersion)")
            
            if compareVersions(release.tagName, isGreaterThan: currentVersion) {
                print("Update available!")
                latestVersion = release.tagName
                changelog = release.body
                isUpdateAvailable = true
                
                // Удаляем проверку Settings.shared.launchedWithFile
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingUpdate = !force // Показываем окно только если это не принудительная проверка
                }
            } else {
                print("No update needed")
                isUpdateAvailable = false
            }
        } catch {
            print("Update check failed with error: \(error)")
            if let decodingError = error as? DecodingError {
                print("Decoding error: \(decodingError)")
            }
        }
        
        isChecking = false
    }
    
    private func compareVersions(_ v1: String, isGreaterThan v2: String) -> Bool {
        let v1Components = v1.replacingOccurrences(of: "v", with: "").split(separator: ".")
        let v2Components = v2.replacingOccurrences(of: "v", with: "").split(separator: ".")
        
        print("Comparing versions: \(v1Components) > \(v2Components)")
        
        // Сравниваем каждый компонент версии как число
        for i in 0..<min(v1Components.count, v2Components.count) {
            guard let num1 = Int(v1Components[i]),
                  let num2 = Int(v2Components[i]) else { continue }
            
            if num1 != num2 {
                return num1 > num2
            }
        }
        
        // Если все компоненты равны, более длинная версия считается большей
        return v1Components.count > v2Components.count
    }
    
    func downloadAndInstallUpdate() async throws {
        let url = URL(string: "https://github.com/iampingvi/MIMP/releases/download/\(latestVersion!)/MIMP.zip")!
        
        return try await withCheckedThrowingContinuation { continuation in
            downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] url, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let url = url else {
                    continuation.resume(throwing: NSError(domain: "UpdateError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Download failed"]))
                    return
                }
                
                Task { @MainActor [weak self] in
                    do {
                        try await self?.handleDownloadedFile(at: url)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            progressObservation = downloadTask?.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
            
            downloadTask?.resume()
        }
    }
    
    private func handleDownloadedFile(at downloadUrl: URL) async throws {
        // Save current playback state
        if let currentTrack = AudioPlayer.shared.currentTrack {
            Settings.shared.lastTrackURL = currentTrack.fileURL
            Settings.shared.lastTrackPosition = AudioPlayer.shared.currentTime
            Settings.shared.lastTrackWasPlaying = AudioPlayer.shared.isPlaying
            Settings.shared.wasUpdated = true
        }
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        // Получаем путь к текущему приложению
        let currentAppURL = Bundle.main.bundleURL.deletingLastPathComponent()
        
        print("Starting update installation...")
        print("Current app location: \(currentAppURL.path)")
        print("Temp directory: \(tempDir.path)")
        
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Распаковываем архив
        print("Unzipping update...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", downloadUrl.path, "-d", tempDir.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("Unzip error output: \(output)")
            throw NSError(domain: "UpdateError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unzip failed: \(output)"])
        }
        
        // Находим .app бандл в распакованных файлах
        print("Looking for app bundle...")
        guard let appBundle = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            print("App bundle not found in: \(try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil))")
            throw NSError(domain: "UpdateError", code: 1, userInfo: [NSLocalizedDescriptionKey: "App bundle not found in update package"])
        }
        
        print("Found app bundle at: \(appBundle.path)")
        
        // Создаем временное имя для старой версии
        let oldAppURL = Bundle.main.bundleURL
        let backupURL = oldAppURL.deletingLastPathComponent().appendingPathComponent("MIMP.old.app")
        
        print("Installing update...")
        do {
            // Если есть старый бэкап, удаляем его
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            
            // Переименовываем текущую версию в .old
            try fileManager.moveItem(at: oldAppURL, to: backupURL)
            
            // Копируем новую версию на место старой
            try fileManager.copyItem(at: appBundle, to: oldAppURL)
            
            print("Cleaning up...")
            // Очищаем временные файлы
            try? fileManager.removeItem(at: tempDir)
            try? fileManager.removeItem(at: downloadUrl)
            
            print("Creating restart script...")
            // Создаем временный скрипт для перезапуска с правильными правами
            let scriptURL = fileManager.temporaryDirectory.appendingPathComponent("restart_mimp.sh")
            let scriptContent = """
            #!/bin/bash
            sleep 1
            rm -rf '\(backupURL.path)'
            open '\(oldAppURL.path)'
            """
            
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            print("Executing restart script...")
            // Запускаем скрипт
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptURL.path]
            try task.run()
            
            // Завершаем текущую версию
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
            
        } catch {
            // В случае ошибки пытаемся восстановить старую версию
            print("Installation failed: \(error)")
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: oldAppURL)
                try? fileManager.moveItem(at: backupURL, to: oldAppURL)
            }
            throw error
        }
    }
    
    deinit {
        progressObservation?.invalidate()
    }
    
    func toggleUpdateWindow() {
        // Изменяем логику переключения окна
        if isUpdateAvailable {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingUpdate.toggle()
            }
        }
    }
}

struct GithubRelease: Codable {
    let tagName: String
    let body: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
    }
} 