# Hermit - TODO

> Track progress by checking off tasks as they are completed.
> Each story ends with a verification step and a commit point.

---

## Phase 1: Project Setup & Base UI

### Story 1.1: Create Xcode Project & Configure Build Settings

> As a developer, I need a properly configured Xcode project so I can start building.

- [x] **1.1.1** Create new Xcode project
  - Template: App → SwiftUI → Swift
  - Product Name: `Hermit`
  - Organization Identifier: `com.hermit`
  - Minimum Deployment Target: iOS 18.0
  - Uncheck "Include Tests" (we'll add test targets manually for better control)

- [x] **1.1.2** Create the entitlements file `Hermit/Hermit.entitlements`
  - Add key `com.apple.developer.kernel.increased-memory-limit` = `true`
  - Assign entitlements file to the Hermit target in Signing & Capabilities

- [x] **1.1.3** Create folder structure inside `Hermit/Hermit/`:
  - `Models/`
  - `Services/`
  - `ViewModels/`
  - `Views/Chat/`
  - `Views/Documents/`
  - `Views/Onboarding/`
  - `Views/Settings/`
  - `Utilities/`

- [x] **1.1.4** Initialize git repository and create `.gitignore` for Xcode/Swift
  - Ignore: `*.xcuserdata`, `DerivedData/`, `.build/`, `*.xcworkspace` (if using SPM), `.DS_Store`
  - Keep: `*.xcodeproj`, `*.entitlements`, `Package.resolved`

**Verify:** Project opens in Xcode, builds successfully (`Cmd+B`), runs on simulator showing default "Hello, world!" screen.

**Commit:** `feat: initialize Hermit Xcode project with entitlements and folder structure`

---

### Story 1.2: Add SPM Dependencies

> As a developer, I need all ML and HuggingFace packages resolved so the project compiles with the full dependency tree.

- [x] **1.2.1** Add `mlx-swift` package
  - URL: `https://github.com/ml-explore/mlx-swift`
  - Version rule: Up to Next Major from `0.10.0`
  - Add product `MLX` to the Hermit target

- [x] **1.2.2** Add `mlx-swift-lm` package
  - URL: `https://github.com/DePasqualeOrg/mlx-swift-lm.git` (fork with swift-tokenizers support)
  - Version rule: Branch `swift-tokenizers`
  - Add products: `MLXLLM`, `MLXEmbedders`, `MLXLMCommon` to the Hermit target

- [x] **1.2.3** Add `swift-tokenizers-mlx` package
  - URL: `https://github.com/DePasqualeOrg/swift-tokenizers-mlx`
  - Version rule: Branch `main`
  - Add product `MLXLMTokenizers` to the Hermit target

- [x] **1.2.4** Add `swift-hf-api-mlx` package
  - URL: `https://github.com/DePasqualeOrg/swift-hf-api-mlx`
  - Version rule: Branch `main`
  - Add products `MLXLMHFAPI`, `MLXEmbeddersHFAPI` to the Hermit target

- [x] **1.2.5** Create a smoke-test file `Hermit/Services/DependencyCheck.swift` that imports all modules:
  ```swift
  import MLX
  import MLXLLM
  import MLXEmbedders
  import MLXLMCommon
  import Accelerate
  import PDFKit
  ```
  This file exists only to verify all imports resolve. Remove after Phase 1.

**Verify:** `Cmd+B` succeeds with zero errors. All imports resolve. SPM packages show in Xcode's Package Dependencies navigator.

**Commit:** `feat: add SPM dependencies (mlx-swift, mlx-swift-lm, tokenizers, hf-api)`

---

### Story 1.3: Define Data Models

> As a developer, I need well-typed data structures so all layers share a common vocabulary.

- [x] **1.3.1** Create `Models/ChatMessage.swift`
  - `struct ChatMessage: Identifiable, Codable`
  - Properties: `id: UUID`, `role: Role` (enum: `.user`, `.assistant`, `.system`), `content: String`, `timestamp: Date`

- [x] **1.3.2** Create `Models/Document.swift`
  - `struct Document: Identifiable, Codable`
  - Properties: `id: UUID`, `name: String`, `fileExtension: String`, `dateAdded: Date`, `chunkCount: Int`, `isProcessed: Bool`

- [x] **1.3.3** Create `Models/TextChunk.swift`
  - `struct TextChunk: Identifiable, Codable`
  - Properties: `id: UUID`, `documentId: UUID`, `text: String`, `embedding: [Float]?`, `chunkIndex: Int`

- [x] **1.3.4** Create `Models/ModelInfo.swift`
  - `struct ModelInfo: Identifiable`
  - Properties: `id: String` (HuggingFace repo ID), `name: String`, `sizeDescription: String`, `isDownloaded: Bool`
  - Static constants: `ModelInfo.embeddingModel` and `ModelInfo.llmModel` with HuggingFace IDs

- [x] **1.3.5** Write unit tests `HermitTests/Models/DataModelTests.swift`
  - Test `ChatMessage` encoding/decoding round-trip (JSON)
  - Test `Document` encoding/decoding round-trip
  - Test `TextChunk` encoding/decoding with nil embedding
  - Test `TextChunk` encoding/decoding with populated embedding ([Float] array)
  - Test `ModelInfo` static constants have correct HuggingFace IDs

**Verify:** All 5 tests pass. `Cmd+U` green.

**Commit:** `feat: define data models (ChatMessage, Document, TextChunk, ModelInfo)`

---

### Story 1.4: Build Tab Navigation & Empty Views

> As a user, I can see a tab bar with Chat, Documents, and Settings tabs, each showing a placeholder screen.

- [x] **1.4.1** Update `ContentView.swift` with a `TabView`
  - Tab 1: Chat (icon: `bubble.left.and.bubble.right.fill`)
  - Tab 2: Documents (icon: `doc.text.fill`)
  - Tab 3: Settings (icon: `gearshape.fill`)
  - Use `.tint()` with the accent color

- [x] **1.4.2** Create `Views/Chat/ChatView.swift`
  - Empty state: centered message "Import a document to start chatting"
  - Text input bar at the bottom (disabled, placeholder text "Ask about your documents...")
  - Send button (disabled)

- [x] **1.4.3** Create `Views/Documents/DocumentListView.swift`
  - Empty state: centered message "No documents yet"
  - Toolbar button "+" in navigation bar (does nothing yet)
  - `NavigationStack` wrapping the list

- [x] **1.4.4** Create `Views/Settings/SettingsView.swift`
  - Sections with placeholder rows:
    - "Models" section: rows for Embedding Model and LLM (showing name, "Not downloaded")
    - "Storage" section: row showing "0 MB used"
    - "About" section: app version, "100% On-Device" badge

- [x] **1.4.5** Build and run on simulator
  - Verify all 3 tabs are tappable and display correct views
  - Verify tab icons and titles render correctly
  - Verify navigation titles appear in each tab

**Verify:** App launches on iPhone 17 Pro simulator. All three tabs navigate correctly. No crashes.

**Commit:** `feat: implement tab navigation with placeholder Chat, Documents, and Settings views`

---

### Story 1.5: Build Chat UI Components

> As a user, I can see a chat interface with styled message bubbles, even though sending is not functional yet.

- [x] **1.5.1** Create `Views/Chat/MessageBubble.swift`
  - Accepts a `ChatMessage`
  - User messages: right-aligned, accent-colored background, white text
  - Assistant messages: left-aligned, secondary background, primary text
  - Rounded corners (20pt), padding, max width ~80% of screen
  - Timestamp displayed subtly below the bubble

- [x] **1.5.2** Create `Views/Chat/StreamingIndicator.swift`
  - Three animated pulsing dots
  - Left-aligned like an assistant message
  - Uses `.opacity` animation with staggered delay

- [x] **1.5.3** Update `ChatView.swift` with full layout
  - `ScrollView` with `ScrollViewReader` for auto-scroll
  - `ForEach` over messages array rendering `MessageBubble`
  - Show `StreamingIndicator` when `isGenerating` is true
  - Bottom input bar: `TextField` + send `Button` with `paperplane.fill` icon
  - Input bar has background blur, sits above keyboard (`.safeAreaInset(edge: .bottom)`)

- [x] **1.5.4** Add hardcoded preview messages for development
  - In `ChatView` preview, inject 3-4 sample messages (user + assistant) to visually verify layout
  - Verify bubbles align correctly, text wraps, timestamps show

- [x] **1.5.5** Write UI preview test
  - Verify `MessageBubble` renders in Xcode Preview for both `.user` and `.assistant` roles
  - Verify `StreamingIndicator` animates in Preview
  - Verify `ChatView` with sample data shows scrollable message list

**Verify:** Xcode Preview (`Cmd+Option+P`) shows chat with sample bubbles. User bubbles on right, assistant on left. Streaming dots animate.

**Commit:** `feat: build chat UI components (MessageBubble, StreamingIndicator, ChatView layout)`

---

### Story 1.6: Build Document List UI

> As a user, I can see a list of imported documents with their metadata and an import button.

- [x] **1.6.1** Update `DocumentListView.swift`
  - `NavigationStack` with title "Documents"
  - `List` of documents showing: name, file extension badge, date added, chunk count
  - Swipe-to-delete gesture (non-functional yet, just the UI)
  - Empty state with SF Symbol `doc.text.magnifyingglass` and instructional text
  - Toolbar "+" button that sets `showImporter = true`

- [x] **1.6.2** Create `Views/Documents/DocumentDetailView.swift`
  - Shows document name, date added, file type
  - Section "Chunks" with a list of chunk previews (first 100 chars of each)
  - Section "Status" showing processing state
  - Placeholder data for now

- [x] **1.6.3** Wire navigation from list to detail
  - `NavigationLink` from each document row to `DocumentDetailView`
  - Pass `Document` to the detail view

- [x] **1.6.4** Add preview data and verify
  - Create 2-3 sample `Document` instances for previews
  - Verify list renders correctly with sample data
  - Verify navigation to detail view works in Preview

**Verify:** Preview shows document list with sample entries. Tapping a row navigates to detail. Empty state shows when list is empty.

**Commit:** `feat: build document list and detail UI with navigation`

---

### Story 1.7: Build Onboarding Screen

> As a first-time user, I see a welcome screen explaining what Hermit does and that I need to download models.

- [x] **1.7.1** Create `Views/Onboarding/OnboardingView.swift`
  - Step 1 (Welcome): App name, tagline "Private AI on your iPhone", privacy explanation, "Get Started" button
  - Step 2 (Download): Two model cards showing download progress (placeholder 0%), "Download Models" button
  - Step 3 (Ready): Success message, "Start Using Hermit" button
  - Page-style navigation between steps (or vertical scroll)

- [x] **1.7.2** Create `Views/Onboarding/DownloadProgressView.swift`
  - Reusable component: model name, size label, `ProgressView` bar, percentage text
  - States: not started, downloading (with progress), completed (checkmark), error (retry button)

- [x] **1.7.3** Add conditional navigation in `HermitApp.swift`
  - Check if models are downloaded (use `@AppStorage("onboardingComplete")` for now)
  - If not: show `OnboardingView`
  - If yes: show `ContentView`

- [x] **1.7.4** Verify in Preview and simulator
  - OnboardingView step 1 renders with welcome text
  - DownloadProgressView shows all 4 states correctly
  - Toggling `@AppStorage` flag switches between Onboarding and main app

**Verify:** App launches to OnboardingView. All steps render. DownloadProgressView shows each state. Can toggle to main app via AppStorage flag.

**Commit:** `feat: build onboarding screen with download progress components`

---

### Story 1.8: Apply Visual Theme & Polish

> As a user, the app has a cohesive dark-mode-first visual identity with the Hermit brand.

- [x] **1.8.1** Define color palette in `Assets.xcassets/Colors/`
  - `AccentColor`: amber/gold (#F5A623)
  - `BackgroundPrimary`: #0F0F0F
  - `BackgroundSecondary`: #1A1A1A
  - `UserBubble`: #2C5F2D
  - `TextSecondary`: #8E8E93

- [x] **1.8.2** Apply colors across all views
  - Tab bar tint: AccentColor
  - Chat bubbles: UserBubble (user), BackgroundSecondary (assistant)
  - Backgrounds: BackgroundPrimary
  - All text: primary or TextSecondary as appropriate

- [x] **1.8.3** Add subtle animations
  - Message bubbles: `.transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))`
  - Tab switching: default SwiftUI tab animation
  - Onboarding step transitions: `.animation(.easeInOut)`

- [x] **1.8.4** Add "100% On-Device" privacy badge
  - Small `HStack` with lock icon + "On-Device" text
  - Display in chat header and settings screen

- [x] **1.8.5** Verify dark mode and light mode
  - Run on simulator in both appearance modes
  - Verify all text is readable, contrast is sufficient
  - Verify AccentColor stands out in both modes

**Verify:** App looks cohesive in both dark and light mode. Colors are consistent across all screens. Animations are smooth.

**Commit:** `feat: apply Hermit visual theme (dark-first palette, animations, branding)`

---

### Story 1.9: Phase 1 Integration Test

> Verify Phase 1 is complete: the app compiles, all views render, navigation works, and the project is ready for Phase 2.

- [x] **1.9.1** Full build verification
  - Clean build folder (`Cmd+Shift+K`) then build (`Cmd+B`)
  - Zero errors, zero warnings (or only expected SPM warnings)

- [x] **1.9.2** Run on iPhone 17 Pro simulator
  - App launches to OnboardingView (or ContentView depending on flag)
  - All 3 tabs work
  - Chat view shows sample messages with correct styling
  - Document list shows empty state
  - Settings shows placeholder model info

- [x] **1.9.3** Run unit tests (`Cmd+U`)
  - All DataModel tests pass

- [x] **1.9.4** Delete `DependencyCheck.swift` smoke-test file (no longer needed)

**Verify:** Everything above passes.

**Commit:** `chore: Phase 1 complete - project setup and base UI`

---

### Story 1.10: FIX — Apply Dark Theme & UI Quality Pass

> The visual theme from Story 1.8 was not properly applied. The app currently shows default iOS light styling instead of the Hermit dark-first design. This story must be completed before continuing to Phase 2.

- [x] **1.10.1** Fix background colors across ALL views
  - `ContentView`: set `.preferredColorScheme(.dark)` on the root view
  - ALL screens must use `BackgroundPrimary` (#0F0F0F) as the base background, not system white
  - Use `.background(Color("BackgroundPrimary"))` or define a Color extension for convenience
  - The tab bar must be dark (use `.toolbarBackground(.visible, for: .tabBar)` + `.toolbarBackground(Color("BackgroundPrimary"), for: .tabBar)`)

- [x] **1.10.2** Fix the "On-Device" badge
  - Must use amber/gold (#F5A623) accent, not default iOS blue
  - Style: pill shape with `.background(Color("AccentColor").opacity(0.15))` and `.foregroundColor(Color("AccentColor"))`
  - Lock icon should be SF Symbol `lock.fill` in accent color
  - Small font size (.caption or .footnote)

- [x] **1.10.3** Fix the tab bar
  - Active tab tint: AccentColor (amber #F5A623), not default blue
  - Inactive tabs: TextSecondary (#8E8E93)
  - Tab bar background: dark, not white
  - Remove the rounded pill highlight on the active tab (that's not standard iOS and looks odd)

- [x] **1.10.4** Fix the chat input bar
  - Background: BackgroundSecondary (#1A1A1A) — not light gray
  - Text field: dark background with light placeholder text
  - Send button icon: AccentColor
  - Subtle top border or shadow to separate from content

- [x] **1.10.5** Fix the chat empty state
  - "No Documents Yet" text: white/light on dark background
  - Subtitle: TextSecondary color
  - Add an SF Symbol illustration (e.g., `doc.text.magnifyingglass`) in accent color, larger size
  - Center vertically in the available space (not pushed to top)

- [x] **1.10.6** Fix the navigation titles
  - "Chat" large title: white text on dark background
  - Use `.navigationBarTitleDisplayMode(.large)` with proper dark styling
  - Navigation bar background must be dark, not white

- [x] **1.10.7** Apply the same dark theme fixes to Documents tab
  - List background: BackgroundPrimary
  - Row backgrounds: BackgroundSecondary
  - Empty state: same pattern as chat (dark background, accent icon, light text)
  - "+" button in toolbar: AccentColor

- [x] **1.10.8** Apply the same dark theme fixes to Settings tab
  - Section backgrounds: BackgroundSecondary
  - List background: BackgroundPrimary
  - Section headers: TextSecondary
  - Row text: white/primary

- [x] **1.10.9** Apply the same dark theme fixes to Onboarding screens
  - Full-screen dark background
  - Accent color for CTAs and progress bars
  - White text for headings, TextSecondary for body

- [x] **1.10.10** Verify the complete visual pass
  - Run on simulator in dark mode → all screens use the Hermit palette, no white/light backgrounds anywhere
  - Run on simulator in light mode → app still forces dark appearance (or adapts gracefully)
  - Tab bar: amber active, gray inactive, dark background
  - All text is legible against dark backgrounds
  - Badge, buttons, and accents use amber/gold consistently
  - Take screenshots of each tab for reference

**Verify:** Every screen in the app uses the dark Hermit theme. No default iOS blue or white backgrounds remain. The app looks intentionally designed, not like a default template.

**Commit:** `fix: apply dark-first Hermit theme across all views (backgrounds, tab bar, badge, inputs)`

---

## Phase 2: Model Download Manager

### Story 2.1: Implement MemoryMonitor Utility

> As a developer, I need a utility to check available RAM so the app can make safe decisions about loading models.

- [x] **2.1.1** Create `Utilities/MemoryMonitor.swift`
  - `@Observable class MemoryMonitor`
  - Property: `availableMemoryMB: Int` (updated periodically)
  - Method: `update()` — reads `os_proc_available_memory()` and converts to MB
  - Method: `hasEnoughMemory(requiredMB: Int) -> Bool`
  - Start a timer (every 5 seconds) that calls `update()`
  - Subscribe to `UIApplication.didReceiveMemoryWarningNotification` → log warning + call `update()`

- [x] **2.1.2** Write unit tests `HermitTests/Utilities/MemoryMonitorTests.swift`
  - Test `update()` returns a value > 0
  - Test `hasEnoughMemory(requiredMB: 100)` returns true (any dev machine has 100MB free)
  - Test `hasEnoughMemory(requiredMB: 999_999)` returns false

**Verify:** Tests pass. MemoryMonitor reports sensible values.

**Commit:** `feat: implement MemoryMonitor utility (os_proc_available_memory wrapper)`

---

### Story 2.2: Implement ModelManager Core (State Machine)

> As a developer, I need a central manager that tracks which models are downloaded and loaded in RAM.

- [x] **2.2.1** Create `Services/ModelManager.swift`
  - `@Observable @MainActor class ModelManager`
  - Enums:
    ```
    enum ModelState { case idle, embeddingLoaded, llmLoaded, transitioning }
    enum DownloadState { case notStarted, downloading(progress: Double), completed, error(String) }
    ```
  - Properties:
    - `modelState: ModelState = .idle`
    - `embeddingDownloadState: DownloadState = .notStarted`
    - `llmDownloadState: DownloadState = .notStarted`
    - `embeddingModelDownloaded: Bool` (computed, checks disk)
    - `llmModelDownloaded: Bool` (computed, checks disk)
  - Private properties:
    - `memoryMonitor: MemoryMonitor`
  - Methods (stubs for now, implementation in next stories):
    - `checkDownloadedModels()` — scans Documents/ for model directories
    - `modelDirectory(for modelId: String) -> URL` — returns path in Documents/models/

- [x] **2.2.2** Implement `checkDownloadedModels()`
  - Check if `Documents/models/embeddings/{modelName}/config.json` exists
  - Check if `Documents/models/llm/{modelName}/config.json` exists
  - Update `embeddingDownloadState` and `llmDownloadState` accordingly

- [x] **2.2.3** Inject `ModelManager` into SwiftUI environment
  - In `HermitApp.swift`: create `@State private var modelManager = ModelManager()`
  - Pass via `.environment(modelManager)`
  - Update `OnboardingView` to read `@Environment(ModelManager.self)` and show real download states
  - Update `SettingsView` to show real download states

- [x] **2.2.4** Write unit tests `HermitTests/Services/ModelManagerTests.swift`
  - Test initial `modelState` is `.idle`
  - Test initial download states are `.notStarted`
  - Test `modelDirectory()` returns a URL inside Documents/models/

**Verify:** Tests pass. OnboardingView reflects real download state (not downloaded).

**Commit:** `feat: implement ModelManager core with state machine and disk checks`

---

### Story 2.3: Implement Model Downloads from HuggingFace

> As a user, I can download both AI models from HuggingFace and see real-time progress.

- [x] **2.3.1** Implement `downloadEmbeddingModel() async throws` in `ModelManager`
  - Use `mlx-swift-lm` / `MLXLMCommon` download APIs to fetch from HuggingFace
  - Model ID: `mlx-community/all-MiniLM-L6-v2-bf16` (or the correct ID for MLXEmbedders)
  - Save to `Documents/models/embeddings/`
  - Update `embeddingDownloadState` with progress as files download
  - Handle errors: network failure, disk full, cancelled

- [x] **2.3.2** Implement `downloadLLMModel() async throws` in `ModelManager`
  - Model ID: `mlx-community/gemma-4-e2b-it-4bit`
  - Save to `Documents/models/llm/`
  - Update `llmDownloadState` with progress
  - Check available disk space before starting (~4 GB needed)
  - Handle errors: network failure, disk full, cancelled

- [x] **2.3.3** Implement download cancellation and resume
  - Store the download `Task` reference
  - `cancelDownload()` method that cancels the Task
  - Update state to `.notStarted` on cancellation
  - Persist download progress state so interrupted downloads can be resumed on next app launch
  - On `startDownloads()`, check if a partial download exists and resume from where it left off (if HF API supports range requests; otherwise restart cleanly)

- [x] **2.3.4** Wire `OnboardingViewModel.swift`
  - `@Observable class OnboardingViewModel`
  - `currentStep: OnboardingStep` (.welcome, .downloading, .ready)
  - `startDownloads()` — calls `modelManager.downloadEmbeddingModel()` then `downloadLLMModel()`
  - `skipToMain()` — for dev/testing, sets onboarding complete without downloading
  - Observe `modelManager.embeddingDownloadState` and `llmDownloadState` for progress

- [x] **2.3.5** Update `OnboardingView.swift` to use real ViewModel
  - Wire "Download Models" button to `viewModel.startDownloads()`
  - Show real progress from `DownloadProgressView` for each model
  - Show error state with retry button
  - When both models downloaded, transition to step 3 (ready)
  - "Start Using Hermit" button sets `@AppStorage("onboardingComplete") = true`

- [x] **2.3.6** Update `SettingsView.swift`
  - Show real download status for each model
  - Show disk space used by each model (FileManager file size calculation)
  - "Delete Models" button that removes model directories and resets to onboarding

- [x] **2.3.7** Test on simulator with network
  - Run app → Onboarding → tap "Download Models"
  - Verify embedding model downloads quickly (~90 MB)
  - Verify LLM model downloads with visible progress (~3.5 GB)
  - Verify both models persist after app restart (kill and relaunch)
  - Verify "Delete Models" in Settings removes files and shows onboarding again

**Verify:** Full download flow works end-to-end on simulator. Models persist across launches. Settings shows real disk usage.

**Commit:** `feat: implement HuggingFace model downloads with progress and persistence`

---

### Story 2.4: Implement Model Loading/Unloading in RAM

> As a developer, the ModelManager can load and unload models from RAM with mutual exclusion.

- [x] **2.4.1** Implement `loadEmbeddingModel() async throws` in `ModelManager`
  - If `modelState == .llmLoaded` → call `unloadLLM()` first
  - Set `modelState = .transitioning`
  - `MLX.GPU.set(cacheLimit: 0)` to flush GPU cache
  - Load model using `MLXEmbedders` API from local disk path
  - Store reference in `embeddingContainer`
  - Set `modelState = .embeddingLoaded`

- [x] **2.4.2** Implement `loadLLM() async throws` in `ModelManager`
  - If `modelState == .embeddingLoaded` → call `unloadEmbedding()` first
  - Set `modelState = .transitioning`
  - Check `memoryMonitor.hasEnoughMemory(requiredMB: 4000)` → throw if insufficient
  - `MLX.GPU.set(cacheLimit: 0)` to flush GPU cache
  - Load model using `MLXLLM` API from local disk path
  - Store reference in `llmContainer`
  - Set `modelState = .llmLoaded`

- [x] **2.4.3** Implement `unloadEmbedding()` and `unloadLLM()`
  - Set container reference to `nil`
  - `MLX.GPU.set(cacheLimit: 0)`
  - Set `modelState = .idle`

- [x] **2.4.4** Implement `unloadAll()`
  - Calls both unload methods
  - Sets `modelState = .idle`

- [x] **2.4.5** Implement `handleMemoryWarning()`
  - Subscribe to `UIApplication.didReceiveMemoryWarningNotification` in init
  - On warning: call `unloadAll()`, log the event

- [x] **2.4.6** Write tests `HermitTests/Services/ModelManagerLoadTests.swift`
  - Test state transitions: idle → embeddingLoaded → idle
  - Test mutual exclusion: loading embedding while LLM is loaded first unloads LLM
  - Test `unloadAll()` resets state to idle
  - Note: actual model loading requires downloaded models, so mock or use integration test flag

**Verify:** Tests pass. State machine transitions are correct. Memory warning handling is wired.

**Commit:** `feat: implement model load/unload with mutual exclusion and memory safety`

---

### Story 2.5: Phase 2 Integration Test

> Verify Phase 2 is complete: models download, persist, load into RAM, and the UI reflects all states correctly.

- [x] **2.5.1** Full end-to-end test on simulator
  - Fresh install → Onboarding → Download both models → "Start Using Hermit"
  - Kill app, relaunch → goes to main app (skips onboarding)
  - Settings shows both models as "Downloaded" with correct sizes
  - Settings → "Delete Models" → relaunch → shows onboarding again

- [x] **2.5.2** Run all unit tests (`Cmd+U`)
  - MemoryMonitor tests pass
  - ModelManager tests pass
  - DataModel tests pass (from Phase 1)

- [x] **2.5.3** Memory verification
  - In Settings, verify RAM indicator shows a sensible value
  - Load embedding model (if testable from UI) → verify RAM usage changes

- [x] **2.5.4** UI quality check — Onboarding & Settings
  - Onboarding screens follow dark theme (dark backgrounds, amber accents, white text)
  - Download progress bars use AccentColor, not default blue
  - Settings rows and sections use BackgroundSecondary on BackgroundPrimary
  - All new UI added in Phase 2 is consistent with the Hermit visual theme
  - No default iOS blue tints or white backgrounds on any screen

**Verify:** Everything above passes.

**Commit:** `chore: Phase 2 complete - model download manager with RAM management`

---

## Phase 3: Embeddings Engine & RAG Pipeline

### Story 3.1: Implement Document Processor (Text Extraction)

> As a user, I can import a TXT or PDF file and the app extracts its text content.

- [x] **3.1.1** Create `Services/DocumentProcessor.swift`
  - `static func extractText(from url: URL) throws -> String`
  - For `.txt` files: `String(contentsOf: url, encoding: .utf8)`
  - For `.pdf` files: `PDFDocument(url:)` → iterate `page(at:).string` for all pages → concatenate
  - Throw descriptive error if PDF has no extractable text (scanned/image PDF)
  - Throw error for unsupported file types

- [x] **3.1.2** Add test fixtures
  - Create `HermitTests/Fixtures/` directory
  - Add a small sample `.txt` file (~500 words)
  - Add a small sample `.pdf` file (text-based, 2-3 pages)

- [x] **3.1.3** Write unit tests `HermitTests/Services/DocumentProcessorTests.swift`
  - Test extracting text from a `.txt` file → returns non-empty string
  - Test extracting text from a `.pdf` file → returns non-empty string
  - Test error thrown for unsupported file extension (e.g., `.png`)
  - Test extracted text from known fixture matches expected content (spot-check first 50 chars)

**Verify:** All 4 tests pass. Text extraction works for both TXT and PDF.

**Commit:** `feat: implement DocumentProcessor for TXT and PDF text extraction`

---

### Story 3.2: Implement Chunking Strategy

> As a developer, I can split extracted text into overlapping chunks of ~300 words.

- [x] **3.2.1** Create `Services/ChunkingStrategy.swift`
  - `static func chunk(text: String, targetWords: Int = 300, overlapWords: Int = 50) -> [String]`
  - Algorithm:
    1. Split text into words
    2. Create chunks of `targetWords` words with `overlapWords` overlap
    3. Ensure no empty chunks
    4. Return array of chunk strings

- [x] **3.2.2** Refine chunking to respect sentence boundaries
  - After splitting by word count, adjust boundaries to the nearest sentence end (`.`, `!`, `?`)
  - If no sentence boundary found within 20% of target, fall back to word boundary

- [x] **3.2.3** Write unit tests `HermitTests/Services/ChunkingStrategyTests.swift`
  - Test empty string → returns empty array
  - Test short text (< 300 words) → returns single chunk with the full text
  - Test exact 300-word text → returns single chunk
  - Test 600-word text with 0 overlap → returns 2 chunks, each ~300 words
  - Test 600-word text with 50 overlap → returns 2+ chunks, verify overlap exists (last words of chunk N appear at start of chunk N+1)
  - Test very long text (2000 words) → returns correct number of chunks
  - Test chunk sizes are all within reasonable range (250-350 words, except possibly last chunk)

**Verify:** All 7 tests pass. Chunks are correctly sized with proper overlap.

**Commit:** `feat: implement text chunking strategy with overlap and sentence boundaries`

---

### Story 3.3: Implement Cosine Similarity Utility

> As a developer, I can compute cosine similarity between embedding vectors efficiently using Accelerate.

- [x] **3.3.1** Create `Utilities/CosineSimilarity.swift`
  - `func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float`
  - Implementation using `Accelerate` / `vDSP`:
    - `vDSP.dot(a, b)` for dot product
    - `vDSP.sumOfSquares(a)` and `vDSP.sumOfSquares(b)` for norms
    - Return `dot / (sqrt(normA) * sqrt(normB))`
    - Handle zero-vector edge case (return 0.0)

- [x] **3.3.2** Add batch search function
  - `func findTopK(query: [Float], candidates: [[Float]], k: Int) -> [(index: Int, score: Float)]`
  - Compute cosine similarity of query against all candidates
  - Return top-K results sorted by score descending

- [x] **3.3.3** Write unit tests `HermitTests/Utilities/CosineSimilarityTests.swift`
  - Test identical vectors → similarity = 1.0 (with float tolerance)
  - Test orthogonal vectors (e.g., [1,0,0] vs [0,1,0]) → similarity = 0.0
  - Test opposite vectors ([1,0] vs [-1,0]) → similarity = -1.0
  - Test known vectors with pre-computed expected similarity
  - Test zero vector → returns 0.0 (no crash)
  - Test `findTopK` with 5 candidates and k=2 → returns 2 results with highest scores
  - Test `findTopK` with k > candidates.count → returns all candidates

**Verify:** All 7 tests pass. Cosine similarity matches expected values within float tolerance (1e-5).

**Commit:** `feat: implement cosine similarity with Accelerate/vDSP and top-K search`

---

### Story 3.4: Implement VectorStore (Persistence)

> As a developer, I can store and retrieve chunks with embeddings, persisted to JSON on disk.

- [x] **3.4.1** Create `Services/VectorStore.swift`
  - `@Observable class VectorStore`
  - In-memory storage: `private(set) var chunks: [TextChunk] = []`
  - `func addChunks(_ newChunks: [TextChunk], forDocument documentId: UUID)` — appends and saves
  - `func chunksForDocument(_ documentId: UUID) -> [TextChunk]` — filter by documentId
  - `func deleteChunks(forDocument documentId: UUID)` — removes chunks and deletes file
  - `func allEmbeddings() -> [(index: Int, embedding: [Float])]` — returns non-nil embeddings with indices

- [x] **3.4.2** Implement JSON persistence
  - `private func save(documentId: UUID)` — encode chunks for that document to `Documents/vector_store/{documentId}.json`
  - `func loadAll()` — scan `Documents/vector_store/` directory, decode all JSON files, populate `chunks`
  - Call `loadAll()` on initialization

- [x] **3.4.3** Implement search method
  - `func search(queryEmbedding: [Float], topK: Int = 3) -> [TextChunk]`
  - Uses `findTopK()` from CosineSimilarity utility
  - Returns the `TextChunk` objects corresponding to top-K matches

- [x] **3.4.4** Write unit tests `HermitTests/Services/VectorStoreTests.swift`
  - Test `addChunks` increases chunk count
  - Test `chunksForDocument` returns only chunks for that document
  - Test `deleteChunks` removes chunks for that document
  - Test persistence: add chunks → create new VectorStore instance → `loadAll()` → chunks are there
  - Test `search` with known embeddings returns correct top-K chunks
  - Test `search` with empty store returns empty array
  - Use a temporary directory for test persistence (not the real Documents/)

**Verify:** All 6 tests pass. Chunks persist and reload correctly. Search returns correct results.

**Commit:** `feat: implement VectorStore with JSON persistence and similarity search`

---

### Story 3.5: Implement EmbeddingService

> As a developer, I can generate embeddings for text chunks using MLXEmbedders and the all-MiniLM-L6-v2 model.

- [x] **3.5.1** Create `Services/EmbeddingService.swift`
  - `class EmbeddingService`
  - Dependencies: `ModelManager`
  - `func embed(text: String) async throws -> [Float]`
    - Ensure embedding model is loaded via `modelManager.loadEmbeddingModel()`
    - Use `MLXEmbedders` API to generate embedding
    - Return 384-dimension Float array
  - `func embed(chunks: [String], progress: @escaping (Int, Int) -> Void) async throws -> [[Float]]`
    - Batch process: embed each chunk, call progress callback after each
    - Return array of embeddings

- [x] **3.5.2** Implement unload after batch
  - After `embed(chunks:)` completes, call `modelManager.unloadEmbedding()` to free RAM
  - This is critical for the memory management strategy

- [x] **3.5.3** Integration test (requires downloaded embedding model)
  - `HermitTests/Services/EmbeddingServiceIntegrationTests.swift`
  - Mark as integration test (skip in CI if model not available)
  - Test: embed a short string → returns array of exactly 384 floats
  - Test: embed two similar sentences → cosine similarity > 0.7
  - Test: embed two unrelated sentences → cosine similarity < 0.5
  - Test: batch embed 3 chunks → returns 3 arrays of 384 floats each

**Verify:** Integration tests pass when embedding model is available on disk. Embedding dimension is consistently 384.

**Commit:** `feat: implement EmbeddingService with MLXEmbedders for all-MiniLM-L6-v2`

---

### Story 3.6: Implement RAGEngine (Ingest Pipeline)

> As a user, I can import a document and the app processes it end-to-end: extract text → chunk → embed → store.

- [x] **3.6.1** Create `Services/RAGEngine.swift`
  - `@Observable class RAGEngine`
  - Dependencies: `DocumentProcessor`, `ChunkingStrategy`, `EmbeddingService`, `VectorStore`, `ModelManager`
  - `func ingestDocument(url: URL, progress: @escaping (String) -> Void) async throws -> Document`
    1. `progress("Extracting text...")`
    2. Extract text via `DocumentProcessor.extractText(from:)`
    3. `progress("Splitting into chunks...")`
    4. Chunk text via `ChunkingStrategy.chunk(text:)`
    5. `progress("Generating embeddings...")`
    6. Generate embeddings via `EmbeddingService.embed(chunks:)`
    7. Create `TextChunk` objects with embeddings
    8. `progress("Saving...")`
    9. Save to `VectorStore`
    10. Return `Document` metadata
    11. Unload embedding model

- [x] **3.6.2** Implement `retrieveContext()` in RAGEngine
  - `func retrieveContext(for query: String, topK: Int = 3) async throws -> [TextChunk]`
    1. Load embedding model
    2. Embed the query string
    3. Unload embedding model
    4. Search `VectorStore` with query embedding
    5. Return top-K chunks

- [x] **3.6.3** Create `ViewModels/DocumentViewModel.swift`
  - `@Observable class DocumentViewModel`
  - Properties: `documents: [Document]`, `isProcessing: Bool`, `processingStatus: String`, `errorMessage: String?`
  - `func importDocument(url: URL) async`
    - Set `isProcessing = true`
    - Call `ragEngine.ingestDocument(url:progress:)`
    - Update `processingStatus` from progress callback
    - Append new `Document` to `documents`
    - Persist document list to `Documents/documents/metadata.json`
    - Set `isProcessing = false`
  - `func deleteDocument(id: UUID)`
    - Remove from `documents` array
    - Delete chunks from `VectorStore`
    - Update persisted metadata
  - `func loadDocuments()` — load metadata.json on init

- [x] **3.6.4** Wire document import UI
  - In `DocumentListView`, attach `.fileImporter(isPresented:allowedContentTypes:)` modifier
    - Allowed types: `.plainText`, `.pdf`
  - On file selection, call `documentViewModel.importDocument(url:)`
  - Show processing overlay with status text from `processingStatus`
  - After completion, document appears in the list

- [x] **3.6.5** Wire document deletion
  - Swipe-to-delete on document rows calls `documentViewModel.deleteDocument(id:)`
  - Confirm with an alert before deleting

- [x] **3.6.6** Update `DocumentDetailView.swift`
  - Show real chunk data from `VectorStore.chunksForDocument(documentId:)`
  - Show chunk count, first 100 chars of each chunk
  - Show embedding status (checkmark if embedding exists)

- [x] **3.6.7** Write unit tests `HermitTests/Services/RAGEngineTests.swift`
  - Test `retrieveContext` returns chunks (using pre-populated VectorStore with known embeddings)
  - Test `retrieveContext` with topK=2 returns exactly 2 results
  - Test `retrieveContext` returns most relevant chunk first (using known vectors)

- [x] **3.6.8** Integration test (requires downloaded embedding model)
  - Import a sample .txt file → verify document appears in list
  - Verify chunks are created (count > 0)
  - Verify embeddings are populated (non-nil, length 384)
  - Call `retrieveContext` with a query related to the document → verify relevant chunks returned

**Verify:** Full ingest pipeline works. Documents appear in list. Chunks have embeddings. Retrieval returns relevant results.

**Commit:** `feat: implement RAG ingest pipeline and document import UI`

---

### Story 3.7: Phase 3 Integration Test

> Verify Phase 3 is complete: documents can be imported, chunked, embedded, stored, and retrieved.

- [x] **3.7.1** End-to-end on simulator
  - Import a TXT file (~500 words) → see it in document list with chunk count
  - Import a PDF file (2-3 pages) → see it in document list
  - Tap a document → detail view shows chunks with first 100 chars
  - Delete a document → it disappears from list
  - Kill app, relaunch → documents and chunks persist

- [x] **3.7.2** Run all unit tests (`Cmd+U`)
  - All Phase 1 tests pass (DataModel)
  - All Phase 2 tests pass (MemoryMonitor, ModelManager)
  - All Phase 3 tests pass (DocumentProcessor, ChunkingStrategy, CosineSimilarity, VectorStore, RAGEngine)

- [x] **3.7.3** Memory check
  - After importing a document, verify embedding model was unloaded
  - Check `modelManager.modelState == .idle` after ingest completes

- [x] **3.7.4** UI quality check — Document import flow
  - Document list uses dark theme (BackgroundPrimary, BackgroundSecondary rows)
  - File importer sheet appears correctly
  - Processing overlay is styled (dark background, amber spinner/progress, white status text)
  - Document detail view uses dark theme with chunk previews legible on dark background
  - Swipe-to-delete uses red destructive style on dark row
  - Empty state after deletion returns to styled empty state (not a blank white screen)

**Verify:** Everything above passes.

**Commit:** `chore: Phase 3 complete - embeddings engine and RAG pipeline`

---

## Phase 4: LLM Inference with Streaming

### Story 4.1: Implement LLMService

> As a developer, I can load Gemma 4 E2B and generate streaming text responses.

- [x] **4.1.1** Create `Services/LLMService.swift`
  - `class LLMService`
  - Dependencies: `ModelManager`
  - Private: `chatSession: ChatSession?`
  - `func loadModel() async throws`
    - Call `modelManager.loadLLM()` (handles mutual exclusion)
    - Create `ChatSession` from the loaded model container

- [x] **4.1.2** Implement streaming generation
  - `func generate(systemPrompt: String, userMessage: String) -> AsyncThrowingStream<String, Error>`
    - Ensure model is loaded
    - Set system prompt on the ChatSession
    - Call `chatSession.streamResponse(to: userMessage)`
    - Forward each token from the stream
    - Handle max token limit (~1024 tokens for responses)

- [x] **4.1.3** Implement model lifecycle methods
  - `func unloadModel()`
    - Set `chatSession = nil`
    - Call `modelManager.unloadLLM()`
  - `func resetConversation() async throws`
    - Create a new `ChatSession` with the same loaded model (clears KV cache / conversation history)
    - Keep the model in RAM

- [x] **4.1.4** Integration test (requires downloaded LLM)
  - `HermitTests/Services/LLMServiceIntegrationTests.swift`
  - Test: load model → model state becomes `.llmLoaded`
  - Test: generate with simple prompt → stream yields at least 1 token
  - Test: generate with system prompt + user message → stream completes with non-empty result
  - Test: unload → model state becomes `.idle`

**Verify:** LLM loads, generates streaming text, and unloads cleanly.

**Commit:** `feat: implement LLMService with ChatSession and streaming generation`

---

### Story 4.2: Implement RAG Query Pipeline

> As a developer, the RAGEngine can orchestrate the full query flow: embed query → retrieve → generate.

- [x] **4.2.1** Add `query()` method to `RAGEngine`
  - `func query(prompt: String, onStatus: @escaping (String) -> Void) -> AsyncThrowingStream<String, Error>`
    1. `onStatus("Searching documents...")`
    2. Call `retrieveContext(for: prompt, topK: 3)`
    3. Build system prompt with retrieved chunks injected
    4. `onStatus("Generating response...")`
    5. Call `llmService.generate(systemPrompt:userMessage:)`
    6. Forward the token stream

- [x] **4.2.2** Define the system prompt template
  - Create a constant or method that builds the prompt:
    ```
    You are a helpful assistant that answers questions based EXCLUSIVELY on the provided context.
    Do not make up information.

    CONTEXT:
    ---
    {chunk texts joined by ---}
    ---

    RULES:
    - Answer ONLY with information from the context above.
    - If the answer is not in the context, say: "I don't find that information in the provided documents."
    - Quote the relevant part of the context when possible.
    - Answer in the same language as the user.
    ```

- [x] **4.2.3** Handle the case where no documents are imported
  - If `vectorStore.chunks` is empty, return an immediate message: "Please import a document first."
  - Do not load any model

- [x] **4.2.4** Handle the case where retrieval returns no relevant chunks
  - If all cosine similarities are below a threshold (e.g., 0.2), include a note in the system prompt that the context may not be relevant

- [x] **4.2.5** Enforce input context length limit (~2K-4K tokens)
  - Before sending system prompt + user message to the LLM, estimate total token count
  - If the assembled prompt (system prompt with injected chunks + user query) exceeds ~3000 tokens, truncate or reduce the number of injected chunks
  - Strategy: start with topK=3 chunks; if prompt too long, reduce to topK=2 or topK=1
  - Log a warning when truncation occurs

- [x] **4.2.6** Write unit tests
  - Test system prompt construction contains the injected chunk text
  - Test empty vector store returns "import document" message without loading models
  - Test prompt template has correct structure (CONTEXT section, RULES section)
  - Test context length limiting: when chunks are very large, verify prompt is truncated to stay under limit

**Verify:** Tests pass. Query pipeline correctly chains retrieval → prompt construction → generation. Context never exceeds safe token limits.

**Commit:** `feat: implement RAG query pipeline with system prompt and context injection`

---

### Story 4.3: Wire Chat UI to RAG Pipeline

> As a user, I can type a question and receive a streaming AI response grounded in my documents.

- [x] **4.3.1** Create `ViewModels/ChatViewModel.swift`
  - `@Observable class ChatViewModel`
  - Properties:
    - `messages: [ChatMessage] = []`
    - `currentStreamedText: String = ""`
    - `isGenerating: Bool = false`
    - `statusMessage: String = ""` (e.g., "Searching...", "Generating...")
    - `errorMessage: String?`
  - Dependencies: `RAGEngine`

- [x] **4.3.2** Implement `sendMessage(text:) async`
  - Append user message to `messages`
  - Set `isGenerating = true`
  - Call `ragEngine.query(prompt:onStatus:)`
  - On each token from stream: append to `currentStreamedText`
  - On stream completion: create assistant `ChatMessage` from `currentStreamedText`, append to `messages`, clear `currentStreamedText`
  - Set `isGenerating = false`
  - On error: set `errorMessage`

- [x] **4.3.3** Implement cancellation
  - Store the generation `Task` reference
  - `func stopGenerating()` — cancels the Task
  - On cancellation: save whatever was streamed so far as the assistant message

- [x] **4.3.4** Implement `clearConversation()`
  - Clear `messages` array
  - Call `llmService.resetConversation()` to clear KV cache
  - Keep model loaded

- [x] **4.3.5** Wire `ChatView.swift` to `ChatViewModel`
  - `@Environment(ChatViewModel.self)` or `@State`
  - `ForEach(viewModel.messages)` → `MessageBubble`
  - Show `currentStreamedText` in a live-updating assistant bubble while generating
  - Show `StreamingIndicator` during the retrieval phase (before first token)
  - Show `statusMessage` as a subtle label above the streaming indicator
  - Text field: on submit or send button tap → call `viewModel.sendMessage(text:)`
  - Disable send button while `isGenerating`
  - Show stop button while generating (replaces send button)
  - Auto-scroll to bottom on new messages

- [x] **4.3.6** Add keyboard handling
  - Text field focuses correctly
  - Keyboard avoidance works (messages scroll up)
  - Send on Return key

- [x] **4.3.7** Inject ChatViewModel into environment
  - Create in `HermitApp.swift`, pass via `.environment()`
  - ChatViewModel depends on RAGEngine → initialize with correct dependencies

- [x] **4.3.8** Write unit tests `HermitTests/ViewModels/ChatViewModelTests.swift`
  - Test `sendMessage` appends a user message to `messages` array
  - Test `isGenerating` is true while generation is in progress
  - Test `stopGenerating` saves partial streamed text as assistant message
  - Test `clearConversation` empties `messages` array
  - Test sending empty string does nothing (messages count unchanged)
  - Test error during generation sets `errorMessage` and `isGenerating = false`

**Verify:** Can type a message, see status updates, and receive streaming response in chat. Stop button works. Clear conversation works. All ChatViewModel tests pass.

**Commit:** `feat: wire chat UI to RAG pipeline with streaming responses`

---

### Story 4.4: Polish Chat Experience

> As a user, the chat feels responsive and polished with proper state handling.

- [x] **4.4.1** Add empty state to ChatView
  - When no messages and documents exist: "Import a document to start chatting" with document icon
  - When no messages but documents exist: "Ask a question about your documents" with prompt suggestions

- [x] **4.4.2** Add error handling UI
  - If generation fails (OOM, model not loaded, etc.): show error inline as a system message bubble
  - Add "Retry" button on error messages
  - If model fails to load: show alert with "Not enough memory" message

- [x] **4.4.3** Add model loading indicator
  - When transitioning from idle/embedding to LLM: show "Loading AI model..." with spinner
  - This can take 5-15 seconds, user needs feedback

- [x] **4.4.4** Add haptic feedback
  - Light haptic on message send
  - Success haptic when generation completes
  - Error haptic on failure

- [x] **4.4.5** Add basic markdown rendering in assistant messages
  - Bold (`**text**`), italic (`*text*`), code blocks (`` `code` ``)
  - Use `AttributedString` with markdown parsing or SwiftUI `Text` with markdown support

- [x] **4.4.6** Add "Clear Conversation" button
  - In navigation toolbar or as a menu option
  - Confirm with alert before clearing
  - Calls `chatViewModel.clearConversation()`

**Verify:** All states are handled gracefully. No crashes on edge cases (empty input, rapid sending, OOM). Chat is responsive and pleasant to use.

**Commit:** `feat: polish chat experience with error handling, haptics, and markdown`

---

### Story 4.5: Settings & System Status

> As a user, I can see which model is loaded, how much RAM is being used, and manage my data.

- [ ] **4.5.1** Update `SettingsView.swift` with live data
  - "Models" section:
    - Embedding model: name, size on disk, download status
    - LLM: name, size on disk, download status
    - Currently loaded model indicator (green dot next to the loaded one)
  - "Memory" section:
    - Available RAM (from MemoryMonitor)
    - Model state (idle / embedding loaded / LLM loaded)
  - "Documents" section:
    - Total documents imported
    - Total chunks stored
    - Total storage used by vector store
  - "Data Management" section:
    - "Delete All Documents" button (with confirmation)
    - "Delete Models" button (with confirmation, returns to onboarding)
    - "Reset App" button (deletes everything)
  - "About" section:
    - App version
    - "100% On-Device" badge
    - Model versions / HuggingFace IDs

- [ ] **4.5.2** Wire all data sources
  - `@Environment(ModelManager.self)` for model states
  - `@Environment(MemoryMonitor.self)` for RAM
  - `@Environment(VectorStore.self)` for document/chunk counts

- [ ] **4.5.3** Verify all actions work
  - "Delete All Documents" removes documents and chunks, chat becomes empty
  - "Delete Models" removes model files, app shows onboarding on next launch
  - RAM indicator updates in real-time

**Verify:** Settings shows accurate, live data. All destructive actions work with confirmation dialogs.

**Commit:** `feat: complete Settings view with live status, memory info, and data management`

---

### Story 4.6: End-to-End Integration Test

> Verify the complete app flow works from first launch to generating a RAG response.

- [ ] **4.6.1** Full flow test on simulator
  1. Fresh install → Onboarding appears
  2. Download models → progress shows → both complete
  3. "Start Using Hermit" → main app with Chat tab
  4. Switch to Documents tab → empty state
  5. Tap "+" → import a sample TXT file
  6. Processing overlay shows: "Extracting text..." → "Splitting into chunks..." → "Generating embeddings..." → "Saving..."
  7. Document appears in list with chunk count
  8. Switch to Chat tab
  9. Type a question related to the document content
  10. See status: "Searching documents..." → "Generating response..."
  11. See streaming response appear token by token
  12. Response is grounded in the document (not hallucinated)
  13. Send a follow-up question → new response streams in

- [ ] **4.6.2** Edge case tests
  - Send empty message → nothing happens (send button disabled)
  - Import a very short TXT (10 words) → creates 1 chunk, still works
  - Import a long PDF (20+ pages) → takes time but completes
  - Ask a question not related to the document → model says "I don't find that information..."
  - Tap stop during generation → partial response is saved
  - Delete all documents → chat shows empty state again
  - Memory warning simulation (if possible on simulator)

- [ ] **4.6.3** Run all unit tests (`Cmd+U`)
  - All Phase 1 tests pass (DataModel)
  - All Phase 2 tests pass (MemoryMonitor, ModelManager)
  - All Phase 3 tests pass (DocumentProcessor, ChunkingStrategy, CosineSimilarity, VectorStore, RAGEngine)
  - All Phase 4 tests pass (ChatViewModel, system prompt)

- [ ] **4.6.4** Performance check
  - Embedding generation for a 10-page document: under 60 seconds
  - First token latency after sending a message: under 15 seconds (includes model load if needed)
  - Streaming speed: visible token-by-token output (not frozen UI)

- [ ] **4.6.5** Final UI quality review — Full app
  - **Global**: No default iOS blue tints anywhere. No white/light backgrounds. All screens use BackgroundPrimary (#0F0F0F)
  - **Tab bar**: amber active icon, gray inactive, dark background, no pill highlight
  - **Chat**: message bubbles (green user, dark gray assistant) are well-padded, rounded, max 80% width. Streaming text is visible against dark background. Input bar is dark with amber send button. Status messages ("Searching...", "Generating...") are visible
  - **Documents**: list rows are dark with clear text. Import button is amber. Processing overlay doesn't obscure content awkwardly. Detail view chunks are readable
  - **Settings**: sections visually separated. Model status clear (green dot for loaded). RAM indicator legible. Destructive buttons are red
  - **Onboarding**: each step feels intentional. Progress bars use amber. CTAs are prominent. Privacy messaging is clear
  - **Transitions & animations**: no jarring jumps between screens. Message appear animation is smooth. Tab switches don't flash white
  - **Typography**: headings are bold SF Pro Display. Body is SF Pro Text. Consistent sizes. Dynamic Type doesn't break layouts
  - **Accessibility**: minimum contrast ratios met (4.5:1 for body text). All interactive elements have adequate tap targets (44pt minimum)

**Verify:** Complete app works end-to-end. All unit tests pass. Performance is acceptable. Every screen follows the Hermit dark theme.

**Commit:** `chore: Phase 4 complete - full RAG pipeline with streaming LLM inference`

---

### Story 4.7: Final Polish & Cleanup

> Prepare the app for demo / testing on a real device.

- [ ] **4.7.1** Remove all hardcoded preview/sample data from production code
  - Sample messages in ChatView → only in `#Preview` blocks
  - Sample documents → only in `#Preview` blocks

- [ ] **4.7.2** Add app icon to `Assets.xcassets/AppIcon.appiconset/`
  - A simple icon (can be a placeholder for MVP)

- [ ] **4.7.3** Review all TODO/FIXME comments in code
  - Resolve or document each one

- [ ] **4.7.4** Test on real iPhone 16 Pro
  - Connect device, configure Developer Mode (see PLANNING.md section 0.2)
  - Build and run on device
  - Verify model download works over Wi-Fi
  - Verify LLM inference works without OOM crash
  - Verify app survives backgrounding and foregrounding
  - Check thermal behavior during sustained inference

- [ ] **4.7.5** Final clean build
  - Clean build folder (`Cmd+Shift+K`)
  - Build (`Cmd+B`) → zero errors
  - Run all tests (`Cmd+U`) → all pass
  - Run on simulator → full flow works

**Verify:** App is MVP-ready. Works on simulator and real device. Clean codebase.

**Commit:** `chore: MVP complete - Hermit v0.1.0`

---

## Summary

| Phase | Stories | Tasks | Tests | UI Quality Gate |
|---|---|---|---|---|
| **Phase 1** | 10 stories | 48 tasks | DataModel (5) | Story 1.10: full dark theme fix |
| **Phase 2** | 5 stories | 24 tasks | MemoryMonitor (3), ModelManager (7) | Task 2.5.4: onboarding & settings |
| **Phase 3** | 7 stories | 31 tasks | DocumentProcessor (4), Chunking (7), CosineSimilarity (7), VectorStore (6), RAGEngine (3+), EmbeddingService (4) | Task 3.7.4: document flow |
| **Phase 4** | 7 stories | 36 tasks | LLMService (4), RAGQuery (4+), ChatViewModel (6), E2E | Task 4.6.5: full app review |
| **Total** | **29 stories** | **139 tasks** | **~55 tests** | **4 quality gates** |
