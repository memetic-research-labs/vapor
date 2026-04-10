# Prompt Compression

Vapor compresses your prompts using the [Prompt-Cloud (PC) compression spec](https://github.com/swbratcher/prompt-cloud/blob/main/prompt_cloud_compression.md). The goal is to reduce token count while preserving **functional equivalence** — the compressed prompt should activate the same semantic patterns in an AI model as the original.

## How It Works

When you press `⌘ ↩`, Vapor sends your text to the selected compression backend with a system prompt that instructs the model to:

1. **Strip grammatical scaffolding** — articles, prepositions, auxiliary verbs, pronouns, conjunctions
2. **Bundle semantically related concepts** into dense lowercase compound tokens
3. **Preserve exact values** — numbers, URLs, paths, dates, identifiers
4. **Preserve negations** — not, never, unless, no (kept visible, never buried in compounds)
5. **Use camelCase only for disambiguation** — default is lowercase fusion
6. **Use minimal whitespace** — break only where ambiguity would result
7. **Compress behavioral/intent content aggressively** — preserve structured data verbatim

### Example

**Input:**
> You are a senior backend engineer reviewing pull requests. Focus on correctness, performance, and maintainability. Be direct but not harsh. If you see a pattern that will cause problems at scale, flag it clearly. Don't nitpick formatting or style unless it hurts readability.

**Output:**
> seniorbackendprReviewer focuscorrectnessperformancemaintainability directnotharsh flagscaleproblems skipformattingstyle unlessreadabilityhurt alwaysexplainwhymatters notwhatswrong

### Token Reduction

Typical compression achieves **40-60% token reduction**. The token count displayed in Vapor uses real BPE tokenization (cl100k_base via Tiktoken), not word-count estimates.

**Screenshot needed:** `screens/compression-result.png` — the expanded view showing original text, compressed preview, and token count stats (e.g., "234 → 98 tokens, 0.42 ratio").

## Compression Backends

Vapor supports three compression backends. Choose in **Settings** (`⌘ ,`).

### Apple Foundation Models (Default)

- **Cost:** Free
- **Download:** None required
- **Requirements:** macOS 26+, Apple Intelligence enabled
- **Quality:** Good for most prompts
- **Speed:** Fast (on-device)
- **Model:** Apple's on-device ~3B parameter model

This is the default because it works immediately with no setup. The model runs entirely on your Mac.

### Local LLM (Recommended for Best Quality)

- **Cost:** Free
- **Download:** ~4.7 GB (one-time)
- **Requirements:** ~8 GB available RAM
- **Quality:** Best — follows complex compression rules more accurately
- **Speed:** Fast (on-device, Metal GPU accelerated)
- **Model:** Qwen2.5-7B-Instruct (Q4_K_M quantization)

The 7B parameter model is significantly better at following the nuanced PC compression rules than Apple's smaller on-device model. It runs locally via llama.cpp with Metal acceleration on Apple Silicon.

**We strongly recommend downloading the local LLM for the best compression quality.** You can download it in Settings > Local LLM Configuration.

**Screenshot needed:** `screens/settings-local-llm.png` — the Settings panel showing Local LLM selected with the Download button or Model ready status.

### OpenRouter (Cloud API)

- **Cost:** ~$0.01 per 1M tokens
- **Download:** None
- **Requirements:** OpenRouter API key
- **Quality:** Depends on the selected model
- **Speed:** Depends on network latency

Use this if you want to use a specific cloud model. Enter your API key and model name in Settings > OpenRouter Configuration.

## Token Counting

Vapor uses real BPE (Byte-Pair Encoding) tokenization via the Tiktoken library with the `cl100k_base` encoding (the same tokenizer used by GPT-4). This gives accurate token counts even for:

- camelCase fused tokens (`highCostOfLiving` = ~5 tokens, not 1)
- Punctuation and special characters
- Non-English text

The stats bar in the expanded view shows:
- **Original tokens** — token count of your input text
- **Compressed tokens** — token count of the compressed output
- **Ratio** — compressed / original (lower is better)

**Screenshot needed:** `screens/stats-bar.png` — close-up of the stats bar showing token counts and ratio.

## LLM Sampling Configuration

The local LLM uses carefully tuned sampling parameters for deterministic compression output:

| Parameter | Value | Why |
|---|---|---|
| Temperature | 0.1 | Near-deterministic — compression is a structured task, not creative writing |
| Top P | 0.9 | Tight probability cutoff to prevent unlikely tokens |
| Repeat Penalty | 1.0 (disabled) | Compression output naturally repeats patterns — penalizing this hurts consistency |
| Seed | 42 | Reproducible output |

For full details, see [LLM Sampling Configuration](llm-sampling-config.md).

## Compress & Copy Workflow

1. Type or dictate your prompt in the editor
2. Press `⌘ ↩` — the status shows "Compressing..."
3. The compressed text is **automatically copied to your clipboard**
4. The status shows "Copied to clipboard" (green checkmark) for 2 seconds
5. Switch to your target app and press `⌘ V` to paste

The compressed text is also saved to your [Prompt History](prompt-history.md) automatically.
