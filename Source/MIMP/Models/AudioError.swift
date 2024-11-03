import Foundation

enum AudioError: Error {
    case unsupportedFormat
    case failedToLoad(Error)
    case failedToAnalyze(Error)
} 