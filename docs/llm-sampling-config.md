# Local LLM Sampling Configuration

## Overview

Vapor uses a local GGUF model (Qwen2.5-7B-Instruct Q4_K_M) via `swift-llama-cpp` for on-device Prompt-Cloud compression. The sampling parameters are tuned specifically for this deterministic compression task, not general-purpose chat.

## Current Configuration

```swift
LlamaSamplingConfig(
    temperature: 0.1,
    seed: 42,
    topP: 0.9,
    repetitionPenaltyConfig: LlamaRepetitionPenaltyConfig(
        lastN: 64,
        repeatPenalty: 1.0,
        freqPenalty: 0.0,
        presentPenalty: 0.0
    )
)
```

## Parameter Rationale

### temperature: 0.1

Controls randomness of token selection. Lower values produce more deterministic output.

- **Why 0.1**: Prompt-Cloud compression is a structured transformation with a well-defined expected output format. The model should follow the compression rules precisely, not explore creative alternatives. A value of 0.1 gives just enough variance to avoid degenerate loops while keeping output tightly focused.
- **Why not 0.0**: Fully greedy decoding (0.0) can occasionally get stuck in repetitive patterns. A small amount of temperature provides an escape hatch.
- **Previous value**: 0.5 — too high, caused inconsistent compression output and occasional commentary instead of compressed text.

### seed: 42

Seed for the random number generator.

- **Why 42**: Ensures reproducibility. Given the same input and parameters, the model produces the same output. Useful for debugging and testing compression quality.

### topP: 0.9 (nucleus sampling)

The cumulative probability cutoff. The model only considers tokens whose combined probability covers this fraction of the total.

- **Why 0.9**: For a deterministic task, we want the model to stay within the high-probability token space. 0.9 cuts off the bottom 10% of unlikely tokens, preventing occasional nonsensical outputs.
- **Previous value**: 0.95 (default) — slightly too permissive for a structured compression task.

### topK: nil (disabled)

Number of most likely tokens to consider. Disabled in favor of topP.

- **Why nil**: topP provides better dynamic filtering than a fixed topK cutoff. For compression output that varies in token predictability, topP adapts naturally.

### repeatPenalty: 1.0 (disabled)

Penalty applied to tokens that have already appeared in the output.

- **Why 1.0 (no penalty)**: Prompt-Cloud compressed output naturally contains repeated structural patterns — dense lowercase compound strings, consistent formatting. A repeat penalty would cause the model to unnecessarily vary its output format, introducing inconsistency. For example, it might compress one concept as lowercase and another as camelCase just to avoid "repeating" the lowercase pattern.
- **Previous value**: 1.1 — actively harmful for this task. The model was penalized for producing consistent compression formatting.

### freqPenalty: 0.0 (disabled)

Penalty proportional to how often a token has appeared.

- **Why 0.0**: Same reasoning as repeatPenalty. Compression output should be format-consistent, not penalized for reusing common tokens.

### presentPenalty: 0.0 (disabled)

Flat penalty for any token that has appeared at all.

- **Why 0.0**: Disabled. No reason to penalize token presence in a structured compression task.

### minKeep: 1 (default)

Minimum number of candidate tokens after sampling filters.

- **Why 1**: Default value. Ensures at least one token is always available for selection even after topP/topK filtering.

## Model Configuration

```swift
LlamaConfig(batchSize: 256, maxTokenCount: 4096, useGPU: true)
```

| Parameter | Value | Notes |
|---|---|---|
| `batchSize` | 256 | Number of tokens processed per batch. Reasonable for Apple Silicon. |
| `maxTokenCount` | 4096 | Context window size. Sufficient for most prompts — compressed output is always shorter than input. |
| `useGPU` | true | Metal acceleration on Apple Silicon. Significantly faster than CPU-only inference. |

## When to Adjust

- **If output is too repetitive or stuck in loops**: Increase temperature slightly (e.g., 0.15–0.2).
- **If output deviates from compression format**: Decrease temperature toward 0.0.
- **If output includes unexpected tokens**: Decrease topP (e.g., 0.85).
- **If switching to a larger model**: These settings should still work. Larger models are generally more instruction-compliant, so you may be able to use temperature 0.0 safely.
- **If switching to a smaller model**: Consider increasing temperature slightly (0.2) to avoid degenerate outputs, and test compression quality carefully.
