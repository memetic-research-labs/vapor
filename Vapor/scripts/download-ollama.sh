#!/bin/bash
set -e

OLLAMA_VERSION="0.5.7"
OLLAMA_URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-darwin"
RESOURCES_DIR="${SRCROOT:-.}/Vapor/Resources"
OLLAMA_BINARY="${RESOURCES_DIR}/ollama"

echo "Downloading Ollama binary v${OLLAMA_VERSION}..."

mkdir -p "${RESOURCES_DIR}"

if [ ! -f "${OLLAMA_BINARY}" ]; then
    curl -L -o "${OLLAMA_BINARY}" "${OLLAMA_URL}"
    chmod +x "${OLLAMA_BINARY}"
    echo "Ollama binary downloaded to ${OLLAMA_BINARY}"
else
    echo "Ollama binary already exists at ${OLLAMA_BINARY}"
fi

echo "Done."
