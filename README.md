# Hermit

**100% on-device RAG for iPhone.** Chat with your documents using a local LLM. No servers, no API keys, no data leaves your phone.

Hermit is a privacy-first iOS app that runs a complete Retrieval-Augmented Generation pipeline entirely on your iPhone. Import PDFs and text files, and ask questions about them in natural language — powered by **Gemma 4 E2B** (4-bit) for generation and **all-MiniLM-L6-v2** for embeddings, running locally on Apple Silicon via MLX.

---

## Features

- **Chat with your documents** — Ask questions in natural language and get answers grounded in your files.
- **Vision support** — Ask questions about photos using the on-device vision language model (Gemma 4 VLM).
- **PDF & text ingestion** — Import documents directly on your phone with automatic text extraction and chunking.
- **Semantic search** — Find relevant content across all your documents using vector similarity, not just keyword matching.
- **Fully offline** — Works without an internet connection after the initial model download.
- **Privacy-first** — Zero data transmitted, zero cloud dependencies, zero telemetry.

## How it works

```
Document Ingestion:
PDF/TXT → Text Extraction → Chunking (≤256 tokenizer tokens, 32-token overlap) → MiniLM Embeddings → Vector Store (JSON)

Query Pipeline:
User Question → Embed Query (MiniLM) → Cosine Similarity Search → Top-K Chunks → LLM Generation (Gemma 4)
```

Choose **General** chat to keep the loaded model and conversation cache between turns. Choose **Documents** to retrieve context from imported files. Only document queries load MiniLM; it unloads before Gemma loads. Importing documents does not automatically enable retrieval for every message.

Hermit uses upstream MLXVLM model loading, image processing, and `ChatSession`. Conversations use structured messages with a 4,096-token total budget, reserving 1,024 tokens for the answer. Old turns are dropped when necessary, then lower-ranked document excerpts; a message that still cannot fit produces a clear error. Changing the prompt prefix or swapping models releases the session cache.

## Tech Stack

| Component | Technology |
|---|---|
| **UI** | SwiftUI, iOS 18+, Swift 6.3 |
| **LLM** | [Gemma 4 E2B 4-bit](https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit) (~3.58 GB) via MLX |
| **Embeddings** | [all-MiniLM-L6-v2](https://huggingface.co/mlx-community/all-MiniLM-L6-v2-bf16) (~90 MB) via MLXEmbedders |
| **ML Runtime** | [mlx-swift](https://github.com/ml-explore/mlx-swift) + [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) |
| **Tokenization** | [swift-tokenizers-mlx](https://github.com/DePasqualeOrg/swift-tokenizers-mlx) |
| **Model Downloads** | [swift-hf-api-mlx](https://github.com/DePasqualeOrg/swift-hf-api-mlx) (HuggingFace Hub) |
| **Vector Store** | In-memory arrays with JSON persistence |
| **Similarity Search** | Apple Accelerate / vDSP cosine similarity |
| **PDF Parsing** | PDFKit (native Apple framework) |

## Requirements

- **Device**: iPhone 15 Pro or later (8 GB RAM minimum)
- **OS**: iOS 18.0+
- **Build**: Mac with Apple Silicon, Xcode 26.4+

> iPhones with 6 GB RAM or less cannot run Gemma 4 E2B. The 4-bit model requires ~4-5 GB just for weights.

## Project Structure

```
Hermit/
├── Models/          # Data structs (ChatMessage, Document, TextChunk, ModelInfo)
├── Services/        # Business logic
│   ├── ModelManager        # Model lifecycle & memory management
│   ├── RAGEngine           # Orchestrates the full RAG pipeline
│   ├── LLMService          # Gemma 4 text generation
│   ├── EmbeddingService    # MiniLM embedding generation
│   ├── VectorStore         # Vector storage & similarity search
│   ├── DocumentProcessor   # PDF/text extraction
│   └── ChunkingStrategy    # Text chunking logic
├── ViewModels/      # @Observable view models
├── Views/           # SwiftUI views (Chat, Documents, Onboarding, Settings)
└── Utilities/       # CosineSimilarity, MemoryMonitor
```

## Memory Management

Running ML models on a phone with limited RAM is the core engineering challenge. Hermit handles this by:

- **Mutual exclusion** — Only one model (LLM or embedding) is loaded at a time. `ModelManager` enforces this.
- **Aggressive cache clearing** — GPU cache is set to zero when unloading models (`MLX.Memory.cacheLimit = 0` and `MLX.Memory.clearCache()`).
- **Memory monitoring** — Checks available memory (`os_proc_available_memory()`) before loading Gemma 4.
- **Increased memory entitlement** — Uses Apple's `increased-memory-limit` entitlement to access ~5-6 GB.

## Dependency update and validation

`project.yml` pins MLX **0.31.4** and official `mlx-swift-lm` **3.31.4**. The checked-in `Package.resolved` also pins transitive dependencies. The tokenizer/Hugging Face adapters retain compatible versions; upgrading their transitive packages independently can break their APIs. No custom Gemma model or vision implementation is maintained by Hermit.

```bash
xcodegen generate
xcodebuild -resolvePackageDependencies -project Hermit.xcodeproj -scheme Hermit
xcodebuild -scheme Hermit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Simulator tests cover app logic; MLX inference requires a physical iPhone. Model integration tests are explicitly disabled unless the test scheme sets `HERMIT_MODEL_TESTS=1`. Download both models before enabling them. Run with parallel testing disabled so model suites cannot compete for GPU memory.

For the iPhone 15 Pro / 8 GB target, measure the following before changing the conservative defaults:

| Comparison | Keep fixed | Record |
|---|---|---|
| Original app vs upstream MLX | Same Gemma weights, prompts and photos | EN/ES answer correctness, photo details, failures |
| Cache 0 / 32 / 64 MB | Same text and image workloads, one model at a time | First-token latency, tokens/s, peak memory, thermal state |
| Embedding batches 1 / 4 / 8 | Same padded inputs and pooling | Import duration, peak memory, cosine/ranking agreement |
| 128 / 192 / 256-token chunks; overlaps 0 / 32 | Same English and Spanish documents/questions | Recall@3 by language, chunk count, import time |
| Dense threshold 0.2 / 0.3 / 0.4; lexical+dense candidate | Same chunks, queries, top-3 context budget | Answerable recall and unanswerable abstention by language |

Use a warm-up and at least five repeats, report medians and p95, and measure text and image prefill separately. Cache stays **0**, batch size stays **1**, and retrieval stays **dense top-3 at 0.2** pending those measurements. No claim of measured iPhone speed or answer-quality improvement is made by the dependency update.

Existing JSON vectors remain compatible: the MiniLM model and pooling are unchanged, and vectors are normalized when loaded. Existing documents retain their old chunks; reimport them to apply token-aware chunking. Any future model/tokenizer/pooling change requires reimporting all documents before comparing retrieval.

## License

MIT
