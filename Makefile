SCHEME := Vapor
PROJECT := Vapor/Vapor.xcodeproj
DERIVED_DATA_PATH := .build/DerivedData

.PHONY: lint test build all download-ollama

# Lint: fast feedback by building the Debug configuration + SwiftLint.
# This effectively type-checks all app sources and SwiftPM dependencies.
lint:
	@echo "[swiftlint] Linting Swift sources with SwiftLint (project .swiftlint.yml)"
	@swiftlint lint --config .swiftlint.yml
	@echo "[lint] Building $(SCHEME) (Debug) with xcodebuild for type-checking"
	xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED_DATA_PATH) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' -quiet build

# Build: explicit Release build of the Vapor app.
build:
	@echo "[build] Building $(SCHEME) (Release) with xcodebuild"
	xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED_DATA_PATH) -scheme $(SCHEME) -configuration Release -destination 'platform=macOS' -quiet build

# Test: run unit + UI tests for the Vapor scheme.
test:
	@echo "[test] Running tests for $(SCHEME)"
	xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED_DATA_PATH) test -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS'

# Download Ollama binary for embedding in app
download-ollama:
	@echo "[download-ollama] Downloading Ollama binary"
	@./Vapor/scripts/download-ollama.sh

# Check: lint + tests.
lint-test: lint test

# Default: lint (Debug build).
all: lint
