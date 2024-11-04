import SwiftUI

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var isRetroMode = false
    
    private var clickCount = 0
    private var lastClickTime = Date()
    
    func handleLogoClick() {
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastClickTime) < 0.5 {
            clickCount += 1
            if clickCount >= 10 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isRetroMode = true
                }
                clickCount = 0
            }
        } else {
            clickCount = 1
        }
        lastClickTime = currentTime
    }
}

extension Color {
    static var retroAccent: Color {
        ThemeManager.shared.isRetroMode ? Color(red: 0.2, green: 0.8, blue: 0.2) : .accentColor
    }
    
    static var retroText: Color {
        ThemeManager.shared.isRetroMode ? Color(red: 0.2, green: 0.8, blue: 0.2) : .white
    }
    
    static var retroBackground: Color {
        ThemeManager.shared.isRetroMode ? Color.black : Color.clear
    }
} 