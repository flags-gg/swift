import Foundation

/// Errors that can occur when working with feature flags
public enum FlagError: Error, CustomStringConvertible, Sendable {
    case httpError(Error)
    case cacheError(String)
    case authError(String)
    case apiError(String)
    case builderError(String)

    public var description: String {
        switch self {
        case .httpError(let error):
            return "HTTP error: \(error.localizedDescription)"
        case .cacheError(let message):
            return "Cache error: \(message)"
        case .authError(let message):
            return "Missing authentication: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .builderError(let message):
            return "Builder error: \(message)"
        }
    }
}
