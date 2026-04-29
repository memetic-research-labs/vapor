# Contributing to Vapor

Thanks for your interest in contributing to Vapor! This guide will help you get started.

## Prerequisites

- macOS 14.0+ (Sonoma)
- Xcode 16+
- Git

## Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/memetic-research-labs/vapor.git
   cd vapor
   ```

2. Open the Xcode project:
   ```bash
   open Vapor/Vapor.xcodeproj
   ```

3. Build and run from Xcode (⌘R).

### Bundle ID Configuration

The app uses a configurable bundle ID prefix so contributors can build with their own identifier (Apple enforces bundle ID uniqueness).

1. Copy the example config:
   ```bash
   cp Vapor/Config.xcconfig.dev.example Vapor/Config.xcconfig.dev
   ```

2. Edit `Config.xcconfig.dev` and set your own prefix:
   ```
   BUNDLE_ID_PREFIX = com.yourname
   ```

Official releases use `lol.mrl.app.Vapor`. Your dev builds will use `com.yourname.Vapor`.

## Development

### Linting

We use SwiftLint. Run it before submitting PRs:

```bash
make lint
```

### Running Tests

```bash
make test
```

### Building

```bash
make build
```

## Pull Request Process

1. **Fork** the repository
2. **Create a branch** from `main` with a descriptive name (e.g., `fix/browser-reconnect`, `feature/new-compressor`)
3. **Make your changes** — keep PRs focused on a single concern
4. **Run lint and tests** before pushing
5. **Open a pull request** against `main`
6. **Respond to review feedback**

### PR Guidelines

- Keep PRs small and focused
- Write clear commit messages explaining the "why" not the "what"
- Add tests for new functionality when possible
- Update documentation if you're changing user-facing behavior

## Code Style

- Follow Swift API Design Guidelines
- Use `swiftlint` rules as the baseline
- Prefer Swift concurrency (async/await) over completion handlers
- Use `@MainActor @Observable` for view models and services
- Use `@Environment` for dependency injection in SwiftUI views

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include macOS version, Vapor version, and steps to reproduce
- Check existing issues before opening a new one

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
