# Hermit — Development Guide

## What is this project?
Hermit is an iOS app (SwiftUI) that performs RAG (Retrieval-Augmented Generation) 100% on-device. No servers, no APIs. It uses Gemma 4 E2B (4-bit MLX) for generation and all-MiniLM-L6-v2 for embeddings.

## Key files
- `PLANNING.md` — Full architecture, memory strategy, data flows, and model details
- `TODO.md` — Granular task list with checkboxes. **This is the source of truth for what to implement next.**

## Tech stack
- **UI**: SwiftUI, iOS 18.0+, Swift 6.3
- **LLM inference**: `mlx-swift` + `mlx-swift-lm` (MLXLLM, MLXEmbedders, MLXLMCommon)
- **Tokenizers**: `swift-tokenizers-mlx` (MLXLMTokenizers)
- **Model downloads**: `swift-hf-api-mlx` (HubClientMLX)
- **Embeddings**: all-MiniLM-L6-v2 via MLXEmbedders
- **Vector search**: In-memory arrays + Accelerate/vDSP cosine similarity
- **PDF reading**: PDFKit (native framework)

## Project structure
```
Hermit/
├── Hermit.xcodeproj
├── Hermit/
│   ├── HermitApp.swift
│   ├── Models/          # Data structs (ChatMessage, Document, TextChunk, ModelInfo)
│   ├── Services/        # Business logic (ModelManager, RAGEngine, LLMService, EmbeddingService, VectorStore, DocumentProcessor, ChunkingStrategy)
│   ├── ViewModels/      # @Observable VMs (ChatViewModel, DocumentViewModel, OnboardingViewModel)
│   ├── Views/           # SwiftUI views organized by feature (Chat/, Documents/, Onboarding/, Settings/)
│   ├── Utilities/       # CosineSimilarity, MemoryMonitor
│   └── Assets.xcassets/
├── HermitTests/
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   ├── Utilities/
│   └── Fixtures/        # Sample .txt and .pdf files for tests
```

## Build & test commands
```bash
# Build (requires Xcode project to exist)
xcodebuild -scheme Hermit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5

# Run tests
xcodebuild -scheme Hermit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20

# Quick build check (just compilation, no linking)
xcodebuild -scheme Hermit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing 2>&1 | tail -5
```

## Critical constraint: Memory management
- iPhone has 8 GB RAM, app can use ~5-6 GB with increased-memory-limit entitlement
- **NEVER** load embedding model (MiniLM) and LLM (Gemma 4) simultaneously
- ModelManager enforces mutual exclusion: load one → unload it → load the other
- Always call `MLX.GPU.set(cacheLimit: 0)` when unloading a model
- Always check `os_proc_available_memory()` before loading Gemma 4

## UI/UX requirements (IMPORTANT)
The app uses a **dark-first** design. This is non-negotiable — every view must follow it:
- **Background**: `BackgroundPrimary` (#0F0F0F) everywhere. No white or system backgrounds.
- **Cards/rows**: `BackgroundSecondary` (#1A1A1A)
- **Accent**: Amber/gold (#F5A623). Never use default iOS blue.
- **Tab bar**: dark background, amber active icon, gray inactive. No pill highlights.
- **User bubbles**: #2C5F2D (dark green). **Assistant bubbles**: BackgroundSecondary.
- **Text**: white primary, #8E8E93 secondary. All text must be legible on dark backgrounds.
- **Input fields**: dark background, not light gray.
- Force dark appearance with `.preferredColorScheme(.dark)` on the root view.

When implementing ANY view, apply these colors. Do not leave default iOS styling. Before marking a UI task as complete, verify colors are applied.

## Git workflow
- Commit after completing each TODO story (group of related subtasks)
- Commit message format: `type: description` (e.g., `feat: implement VectorStore with JSON persistence`)
- Types: `feat`, `fix`, `chore`, `test`, `refactor`
- Always stage specific files, never `git add -A`
- Check off completed items in TODO.md with `[x]` before committing

## Conventions
- Use `@Observable` (not ObservableObject) for view models and services
- Use `@MainActor` on view models and UI-bound services
- Use SwiftUI `.environment()` for dependency injection
- Prefer `async/await` and `AsyncThrowingStream` over closures/callbacks
- Keep services stateless where possible; state lives in ViewModels or Managers
- Test file naming: `{ClassName}Tests.swift` in matching subdirectory under HermitTests/

## SPM Dependencies (exact packages)
| Package | URL | Version |
|---|---|---|
| mlx-swift | https://github.com/ml-explore/mlx-swift | from: 0.10.0 |
| mlx-swift-lm | https://github.com/DePasqualeOrg/mlx-swift-lm.git | branch: swift-tokenizers |
| swift-tokenizers-mlx | https://github.com/DePasqualeOrg/swift-tokenizers-mlx | branch: main |
| swift-hf-api-mlx | https://github.com/DePasqualeOrg/swift-hf-api-mlx | branch: main |

## HuggingFace model IDs
- Embeddings: `mlx-community/all-MiniLM-L6-v2-bf16` (~90 MB)
- LLM: `mlx-community/gemma-4-e2b-it-4bit` (~3.58 GB)
