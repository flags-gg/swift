# FlagsSwift

Swift library for [Flags.gg](https://flags.gg) - A feature flag management service.

This library is a Swift port of [flags-rs](https://github.com/flags-gg/flags-rs), maintaining feature parity with the Rust implementation.

## Features

- **Simple API**: Fluent interface for checking feature flags
- **Caching**: Built-in memory cache with configurable TTL
- **Circuit Breaker**: Automatic failure handling and recovery
- **Local Overrides**: Environment variable support for testing and development
- **Batch Operations**: Check multiple flags efficiently in a single operation
- **Error Handling**: Comprehensive error handling with callbacks
- **Swift Concurrency**: Full support for async/await
- **Cross-Platform**: Works on macOS, iOS, tvOS, and watchOS

## Requirements

- Swift 5.9+
- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/flags-gg/swift.git", from: "1.0.1")
]
```

Or in Xcode, use File > Add Packages and enter the repository URL.

## Quick Start

```swift
import FlagsGG

// Initialize the client
let flags = try Flags.builder()
    .withAuth(Auth(
        projectId: "your-project-id",
        agentId: "your-agent-id",
        environmentId: "your-environment-id"
    ))
    .build()

// Check if a flag is enabled
let isEnabled = await flags.is("my-feature").enabled()

if isEnabled {
    // Feature is enabled
}
```

## Usage

### Basic Flag Checking

```swift
// Check a single flag
let enabled = await FlagsClient.is("my-feature").enabled()
```

### Batch Operations

```swift
// Get multiple flags at once (more efficient than checking individually)
let flags = await FlagsClient.getMultiple(["feature-1", "feature-2", "feature-3"])
for (name, enabled) in flags {
    print("\(name): \(enabled)")
}

// Check if all flags are enabled
if await FlagsClient.allEnabled(["feature-1", "feature-2"]) {
    // All features are enabled
}

// Check if any flags are enabled
if await FlagsClient.anyEnabled(["premium", "beta"]) {
    // At least one feature is enabled
}
```

### List All Flags

```swift
let flags = try await FlagsClient.list()
for flag in flags {
    print("\(flag.details.name): \(flag.enabled)")
}
```

### Error Handling

```swift
let client = try FlagsClient.builder()
    .withAuth(auth)
    .withErrorCallback { error in
        print("Flag error: \(error)")
        // Send to logging service, etc.
    }
    .build()
```

### Configuration

```swift
let client = try FlagsClient.builder()
    .withAuth(auth)
    .withBaseURL("https://custom-api.example.com")
    .withMaxRetries(5)
    .withErrorCallback { error in
        // Handle errors
    }
    .build()
```

## Local Flag Overrides

You can override remote flags using environment variables prefixed with `FLAGS_`. This is useful for testing and development.

```bash
# Set environment variables
export FLAGS_MY_FEATURE=true
export FLAGS_BETA_MODE=false
```

```swift
// These will use the environment variable values
let myFeature = await client.is("my-feature").enabled()  // true
let betaMode = await client.is("beta-mode").enabled()    // false
```

Flag names are normalized, so these are all equivalent:
- `FLAGS_MY_FEATURE`
- `my-feature` (converted from underscores)
- `my feature` (with spaces)
- `my_feature` (original)

## Working Without Authentication

You can use the client without API authentication to only use local flags:

```swift
let client = try FlagsClient.builder().build()

// Will only check FLAGS_* environment variables
let enabled = await client.is("my-feature").enabled()
```

## Architecture

### Core Components

- **Client**: Main interface for interacting with feature flags
- **ClientBuilder**: Fluent builder for configuring the client
- **Cache**: Protocol-based caching system (default: MemoryCache)
- **Circuit Breaker**: Protects against API failures with automatic recovery
- **Local Overrides**: Environment variable support with name normalization

### Design Patterns

1. **Builder Pattern**: Fluent interface for client configuration
2. **Actor Model**: Thread-safe client using Swift actors
3. **Protocol-Oriented**: Extensible cache system via protocols
4. **Graceful Degradation**: Falls back to cached/local flags on API failure

## Error Handling

The library uses comprehensive error handling:

- `httpError`: Network or HTTP errors
- `cacheError`: Cache operation errors
- `authError`: Authentication errors
- `apiError`: API response errors
- `builderError`: Configuration errors

Errors are logged via the error callback and the client gracefully degrades to cached or local flags when the API is unavailable.

## Examples

See the `Examples/` directory for complete working examples:

- `Basic.swift`: Basic usage of the library
- `LocalOverrides.swift`: Using environment variables for local development

To run an example:

```bash
cd flags-swift
swift run Basic
```

## Development

### Building

```bash
swift build
```

### Testing

```bash
swift test
```

### Running Examples

```bash
# Basic example
swift run Basic

# Local overrides example
FLAGS_MY_FEATURE=true swift run LocalOverrides
```

## API Compatibility

This library maintains API compatibility with the Rust implementation ([flags-rs](https://github.com/flags-gg/flags-rs)), with Swift-specific idioms:

| Rust API | Swift API |
|----------|-----------|
| `client.is("name").enabled().await` | `await client.is("name").enabled()` |
| `client.list().await?` | `try await client.list()` |
| `client.get_multiple(&[...]).await` | `await client.getMultiple([...])` |
| `client.all_enabled(&[...]).await` | `await client.allEnabled([...])` |
| `client.any_enabled(&[...]).await` | `await client.anyEnabled([...])` |

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

- Homepage: https://flags.gg
- GitHub Issues: https://github.com/flags-gg/flags-swift/issues
- Documentation: https://docs.flags.gg
