# Hermit — Development Guide

## What is this project?
Hermit is an iOS app (SwiftUI) that performs RAG (Retrieval-Augmented Generation) 100% on-device. No servers, no APIs. It uses Gemma 4 E2B (4-bit MLX) for generation and all-MiniLM-L6-v2 for embeddings.

## Key files
- `PLANNING.md` — Full architecture, memory strategy, data flows, and model details
- `TODO.md` — Granular task list with checkboxes. **This is the source of truth for what to implement next.**

## Tech stack
- **UI**: SwiftUI, iOS 18.0+, Swift 6.3
- **LLM inference**: `mlx-swift` + `mlx-swift-lm` (MLXVLM, MLXEmbedders, MLXLMCommon)
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
- Always call `MLX.Memory.cacheLimit = 0` and `MLX.Memory.clearCache()` when unloading a model
- Always check `os_proc_available_memory()` before loading Gemma 4

## iOS 26 Liquid Glass — CRITICAL (READ THIS)
iOS 26 introduced "Liquid Glass" which makes `TabView`, `NavigationStack`, `List`, toolbars, and tab bars render with a floating translucent card style. This BREAKS our dark-first design. Rules:
- **DO NOT use `TabView`** for the main tab bar. We use a custom `ZStack`-based tab bar in `ContentView.swift`.
- **DO NOT use `NavigationStack`** for top-level views. Use a manual `VStack` header with the title and toolbar buttons instead.
- **DO NOT use `List`** for settings/documents. Use `ScrollView` + `VStack` + custom row backgrounds instead.
- **DO NOT use `.toolbarBackground()`** — it conflicts with Liquid Glass. Instead, build headers manually.
- All backgrounds must use `.ignoresSafeArea()` to fill edge-to-edge.
- If you must use `NavigationStack` (e.g., for deep navigation), wrap it carefully and test that no floating card appears.

## UI/UX requirements (IMPORTANT)
The app uses a **dark-first** design. This is non-negotiable — every view must follow it:
- **Background**: `BackgroundPrimary` (#0F0F0F) everywhere with `.ignoresSafeArea()`. No white or system backgrounds.
- **Cards/rows**: `BackgroundSecondary` (#1A1A1A) with `RoundedRectangle(cornerRadius: 12)`.
- **Accent**: Amber/gold (#F5A623). Never use default iOS blue.
- **Tab bar**: Custom (not system TabView). Dark background, amber active icon, gray inactive. No pill highlights.
- **User bubbles**: #2C5F2D (dark green). **Assistant bubbles**: BackgroundSecondary.
- **Text**: white primary, #8E8E93 secondary. All text must be legible on dark backgrounds.
- **Input fields**: dark `BackgroundSecondary` background, not light gray.
- **Section headers**: use `Text("TITLE").font(.caption.bold()).foregroundStyle(Color("TextSecondary"))` manually.
- Force dark appearance with `.preferredColorScheme(.dark)` on the root view in `HermitApp.swift`.

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
- MiniLM requires untruncated/unpadded tokenization and masked mean pooling with L2 normalization. Its MLX checkpoint lacks pooling metadata. Increment `TextChunk.currentEmbeddingVersion` for any embedding/tokenizer/pooling change; never mix old vectors with new queries.
- Keep services stateless where possible; state lives in ViewModels or Managers
- Test file naming: `{ClassName}Tests.swift` in matching subdirectory under HermitTests/

## SPM Dependencies (exact packages)
| Package | URL | Version |
|---|---|---|
| mlx-swift | https://github.com/ml-explore/mlx-swift | exact: 0.31.4 |
| mlx-swift-lm | https://github.com/ml-explore/mlx-swift-lm.git | revision: 68947ccdca79bcf7a26dc220f73caa060369513c |
| swift-tokenizers-mlx | https://github.com/DePasqualeOrg/swift-tokenizers-mlx | exact: 0.3.0 |
| swift-hf-api-mlx | https://github.com/DePasqualeOrg/swift-hf-api-mlx | exact: 0.2.0 |
| swift-tokenizers | https://github.com/DePasqualeOrg/swift-tokenizers | exact: 0.5.0 |
| swift-hf-api | https://github.com/DePasqualeOrg/swift-hf-api | exact: 0.3.2 |

## HuggingFace model IDs
- Embeddings: `mlx-community/all-MiniLM-L6-v2-bf16` (~90 MB)
- LLM: `mlx-community/gemma-4-e2b-it-4bit` (~3.58 GB)
