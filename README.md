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
PDF/TXT → Text Extraction → Chunking (~300 words) → MiniLM Embeddings → Vector Store (JSON)

Query Pipeline:
User Question → Embed Query (MiniLM) → Cosine Similarity Search → Top-K Chunks → LLM Generation (Gemma 4)
```

Models are swapped in and out of memory since both can't fit simultaneously — the embedding model loads for vectorization, then unloads before the LLM loads for generation.

## Tech Stack

| Component | Technology |
|---|---|
| **UI** | SwiftUI, iOS 18+, Swift 6.3 |
| **LLM** | [Gemma 4 E2B 4-bit](https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit) (~3.58 GB) via MLX |
| **Embeddings** | [all-MiniLM-L6-v2](https://huggingface.co/mlx-community/all-MiniLM-L6-v2-bf16) (~90 MB) via MLXEmbedders |
| **ML Runtime** | [mlx-swift](https://github.com/ml-explore/mlx-swift) + [mlx-swift-lm](https://github.com/DePasqualeOrg/mlx-swift-lm) |
| **Tokenization** | [swift-tokenizers-mlx](https://github.com/DePasqualeOrg/swift-tokenizers-mlx) |
| **Model Downloads** | [swift-hf-api-mlx](https://github.com/DePasqualeOrg/swift-hf-api-mlx) (HuggingFace Hub) |
| **Vector Store** | In-memory arrays with JSON persistence |
| **Similarity Search** | Apple Accelerate / vDSP cosine similarity |
| **PDF Parsing** | PDFKit (native Apple framework) |

## Requirements

- **Device**: iPhone 15 Pro or later (8 GB RAM minimum)
- **OS**: iOS 18.0+
- **Build**: Mac with Apple Silicon, Xcode 26+

> iPhones with 6 GB RAM or less cannot run Gemma 4 E2B. The 4-bit model requires ~4-5 GB just for weights.

## Project Structure

```
Hermit/
├── Models/          # Data structs (ChatMessage, Document, TextChunk, ModelInfo)
├── Services/        # Business logic
│   ├── ModelManager        # Model lifecycle & memory management
│   ├── RAGEngine           # Orchestrates the full RAG pipeline
│   ├── LLMService          # Gemma 4 text generation
│   ├── Gemma4VLM           # Vision language model support
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
- **Aggressive cache clearing** — GPU cache is set to zero when unloading models (`MLX.GPU.set(cacheLimit: 0)`).
- **Memory monitoring** — Checks available memory (`os_proc_available_memory()`) before loading Gemma 4.
- **Increased memory entitlement** — Uses Apple's `increased-memory-limit` entitlement to access ~5-6 GB.

## License

MIT
