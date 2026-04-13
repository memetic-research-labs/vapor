#!/bin/bash
set -e

OLLAMA_VERSION="0.20.5"
OLLAMA_URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-darwin.tgz"
RESOURCES_DIR="${SRCROOT:-.}/Vapor/Resources"
OLLAMA_BINARY="${RESOURCES_DIR}/ollama"

mkdir -p "${RESOURCES_DIR}"

if [ ! -f "${OLLAMA_BINARY}" ]; then
    echo "Downloading Ollama v${OLLAMA_VERSION}..."
    TMPDIR=$(mktemp -d)
    curl -L -o "${TMPDIR}/ollama-darwin.tgz" "${OLLAMA_URL}"
    tar -xzf "${TMPDIR}/ollama-darwin.tgz" -C "${TMPDIR}"

    EXTRACTED=$(find "${TMPDIR}" -name "ollama" -type f | head -1)
    if [ -z "${EXTRACTED}" ]; then
        echo "Error: ollama binary not found in archive"
        rm -rf "${TMPDIR}"
        exit 1
    fi

    cp "${EXTRACTED}" "${OLLAMA_BINARY}"
    chmod +x "${OLLAMA_BINARY}"
    rm -rf "${TMPDIR}"
    echo "Ollama v${OLLAMA_VERSION} installed to ${OLLAMA_BINARY}"
else
    echo "Ollama binary already exists at ${OLLAMA_BINARY}"
fi

echo "Done."
