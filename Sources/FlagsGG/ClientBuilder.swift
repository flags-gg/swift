import Foundation

/// Builder for creating a Client instance
public struct ClientBuilder: Sendable {
    private let baseURL: String
    private let maxRetries: UInt32
    private let auth: Auth?
    private let errorCallback: (@Sendable (FlagError) -> Void)?

    private static let defaultBaseURL = "https://api.flags.gg"
    private static let defaultMaxRetries: UInt32 = 3

    internal init(
        baseURL: String = defaultBaseURL,
        maxRetries: UInt32 = defaultMaxRetries,
        auth: Auth? = nil,
        errorCallback: (@Sendable (FlagError) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.maxRetries = maxRetries
        self.auth = auth
        self.errorCallback = errorCallback
    }

    /// Set the base URL for the API
    /// - Parameter baseURL: The base URL
    /// - Returns: A new builder with the base URL set
    public func withBaseURL(_ baseURL: String) -> ClientBuilder {
        return ClientBuilder(
            baseURL: baseURL,
            maxRetries: maxRetries,
            auth: auth,
            errorCallback: errorCallback
        )
    }

    /// Set the maximum number of retries
    /// - Parameter maxRetries: The maximum number of retries
    /// - Returns: A new builder with max retries set
    public func withMaxRetries(_ maxRetries: UInt32) -> ClientBuilder {
        return ClientBuilder(
            baseURL: baseURL,
            maxRetries: maxRetries,
            auth: auth,
            errorCallback: errorCallback
        )
    }

    /// Set the authentication credentials
    /// - Parameter auth: The authentication credentials
    /// - Returns: A new builder with auth set
    public func withAuth(_ auth: Auth) -> ClientBuilder {
        return ClientBuilder(
            baseURL: baseURL,
            maxRetries: maxRetries,
            auth: auth,
            errorCallback: errorCallback
        )
    }

    /// Set a callback for error handling
    /// - Parameter callback: A closure that will be called when errors occur
    /// - Returns: A new builder with error callback set
    public func withErrorCallback(_ callback: @escaping @Sendable (FlagError) -> Void) -> ClientBuilder {
        return ClientBuilder(
            baseURL: baseURL,
            maxRetries: maxRetries,
            auth: auth,
            errorCallback: callback
        )
    }

    /// Build the client
    /// - Returns: A configured Client instance
    /// - Throws: FlagError if validation fails
    public func build() throws -> Client {
        // Validate auth if provided
        if let auth = auth {
            if auth.projectId.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FlagError.builderError("Project ID cannot be empty")
            }
            if auth.agentId.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FlagError.builderError("Agent ID cannot be empty")
            }
            if auth.environmentId.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FlagError.builderError("Environment ID cannot be empty")
            }
        }

        // Validate base URL
        if baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
            throw FlagError.builderError("Base URL cannot be empty")
        }

        // Validate max retries
        if maxRetries > 10 {
            throw FlagError.builderError("Max retries cannot exceed 10")
        }

        let cache = MemoryCache()

        return Client(
            baseURL: baseURL,
            maxRetries: maxRetries,
            auth: auth,
            cache: cache,
            errorCallback: errorCallback
        )
    }
}
