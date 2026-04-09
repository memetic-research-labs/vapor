# Vapor

A macOS floating text editor that compresses prompts using the [prompt-cloud technique](https://github.com/swbratcher/prompt-cloud), reducing token count while preserving semantic intent.

## Features

- **Prompt-cloud compression** — strips filler words, fuses concepts into dense lowercase compounds
- **4 compression backends** — Rule-based (local), Local LLM (Qwen 2.5 3B via SwiftLlama), OpenRouter (cloud), Apple Foundation Models (macOS 26+)
- **Speech dictation** — hold Fn key to dictate via Apple Speech
- **OpenRouter test sidebar** — validate compression quality by sending compressed prompts
- **Keychain persistence** — API keys stored securely
- **SwiftData history** — prompt history persisted locally

## Compression Example

**Original** (36 words):
> write a web component that renders a canvas that changes color from blue to golden as the time of day changes mimicking the light as it would be where you are located if there were no clouds out site in the sky

**Compressed** (15 words):
> webcomponent renders canvas changes color time day mimics sky location clouds out site sky

The compressed prompt was sent to OpenRouter and produced a complete, working sky simulation web component.

## Requirements

- macOS 15.0+
- Xcode 16+
- ~2GB storage for Qwen 2.5 3B model (first-run download)

## Building

```bash
cd Vapor
open Vapor.xcodeproj
# Build & Run from Xcode
```