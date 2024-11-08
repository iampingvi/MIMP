import SwiftUI
import UniformTypeIdentifiers
import CoreServices
import AppKit

@MainActor
struct FirstLaunchView: View {
    @Binding var isPresented: Bool
    @State private var isSuccess = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Welcome to MIMP!")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(height: 28)
            
            HStack(spacing: 30) {
                // Column 1 - App Icon
                VStack(alignment: .center, spacing: 8) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(15)
                    }
                }
                .frame(width: 120)

                // Column 2 - Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Would you like to set MIMP\nas the default player?")
                        .font(.system(size: 11))
                }
                .frame(width: 140, alignment: .leading)

                // Column 3 - Formats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Formats: (\(AudioFormat.formatsDescription))")
                        .font(.system(size: 11))
                }
                .frame(width: 120)
                
                // Buttons
                VStack(spacing: 8) {
                    Button(action: {
                        Task {
                            do {
                                try await setAsDefaultPlayer()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isPresented = false
                                    Settings.shared.isFirstLaunch = false
                                }
                            } catch {
                                print("Failed to set as default player:", error)
                            }
                        }
                    }) {
                        Text("Set as Default")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                            Settings.shared.isFirstLaunch = false
                        }
                    }) {
                        Text("Skip")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 120)
        .background(
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
        )
    }
    
    @MainActor
    private func setAsDefaultPlayer() async throws {
        nonisolated let workspace = NSWorkspace.shared
        var successCount = 0
        var failedFormats: [String] = []
        
        print("\n=== MIMP Default Player Setup ===")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("App URL: \(Bundle.main.bundleURL.path)")
        
        // Register for all audio files
        if let audioType = UTType("public.audio") {
            try await workspace.setDefaultApplication(
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
                                try await workspace.setDefaultApplication(
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
                    try await workspace.setDefaultApplication(
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