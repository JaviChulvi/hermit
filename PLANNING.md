> Actualización de implementación (2026-09-19): Hermit usa MLXVLM/ChatSession de upstream (commit 68947cc, con el arreglo de carga E2B posterior a 3.31.4), sin Gemma propio. Chunking de hasta 256 tokens con el tokenizer real (solapamiento 32); sesiones persistentes con presupuesto total de 4096 tokens, incluidos 1024 de respuesta; modos General/Documentos; I/O de documentos fuera de MainActor. Las propuestas históricas de abajo sobre chunks de 300 palabras y carga manual quedan sustituidas. Versiones, comportamiento actual y mediciones pendientes: [README](README.md#dependency-update-and-validation).

# Hermit - RAG 100% On-Device para iOS

> **Retrieval-Augmented Generation privado y local.** Sin servidores, sin APIs, sin telemetría. Tus datos nunca salen del iPhone.

---

## 0. Prerrequisitos (Primera vez en desarrollo iOS)

### 0.1 Hardware necesario

| Componente | Requisito mínimo | Recomendado |
|---|---|---|
| **Mac** | Cualquier Mac con Apple Silicon (M1+) | M2 Pro o superior (compilación más rápida) |
| **macOS** | Sequoia 15.6+ | Tahoe 26.2+ |
| **iPhone para testing** | iPhone 15 Pro (8 GB RAM) | iPhone 16 Pro / 17 Pro (8-12 GB RAM) |
| **Espacio en disco (Mac)** | 40 GB libres | 60 GB+ (Xcode + simuladores + caché SPM) |

> **Nota:** iPhones con 6 GB de RAM o menos (iPhone 14, iPhone 15 no-Pro) **no pueden** ejecutar Gemma 4 E2B. El modelo 4-bit requiere ~4-5 GB solo para los pesos.

### 0.2 Software a instalar

#### Paso 1: Xcode

```bash
# Opción A: Desde la Mac App Store (recomendado)
# Buscar "Xcode" → Instalar (~8 GB descarga)

# Opción B: Descarga directa
# https://developer.apple.com/downloads → Xcode 26.x (.xip)
```

- Xcode incluye: compilador Swift, simulador iOS, Interface Builder, Instruments (profiler), y todos los SDKs.
- **Primera apertura:** Xcode pedirá instalar componentes adicionales. Acepta y espera (~5 min).

#### Paso 2: Command Line Tools

```bash
xcode-select --install
```

Instala git, clang, make, y utilidades de compilación (~700 MB).

#### Paso 3: Cuenta de Apple Developer

- **Cuenta gratuita** (suficiente para desarrollo y testing en dispositivo):
  - Crear en [developer.apple.com](https://developer.apple.com)
  - Permite ejecutar apps en tu iPhone directamente desde Xcode
  - Limitación: provisioning profiles expiran cada 7 días (reconectar Xcode y re-ejecutar)
  - Máximo 3 apps sideloaded simultáneamente
- **Cuenta de pago ($99/año):** Solo necesaria para distribuir en App Store o TestFlight.

#### Paso 4: Configurar iPhone para desarrollo

1. Conectar iPhone al Mac por USB (o por Wi-Fi una vez configurado).
2. En el iPhone: **Ajustes → Privacidad y Seguridad → Modo de Desarrollador → Activar**.
3. En Xcode: **Window → Devices and Simulators** → verificar que aparece el dispositivo.
4. La primera vez que ejecutes una app, el iPhone pedirá "confiar en este desarrollador" en **Ajustes → General → VPN y gestión de dispositivos**.

### 0.3 Verificar la instalación

```bash
# Comprobar que Xcode y Swift están correctamente instalados
swift --version        # Debe mostrar Swift 6.x
xcodebuild -version   # Debe mostrar Xcode 26.x
xcrun simctl list devices available | head -20  # Lista simuladores disponibles
```

---

## 1. Arquitectura del Sistema

### 1.1 Diagrama de alto nivel

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Layer                        │
│  ┌───────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │ ChatView  │  │ DocumentView │  │ SettingsView         │ │
│  └─────┬─────┘  └──────┬───────┘  └──────────┬───────────┘ │
│        │               │                      │             │
│  ┌─────▼───────────────▼──────────────────────▼───────────┐ │
│  │              @Observable ViewModels                     │ │
│  │  ChatViewModel · DocumentViewModel · SettingsViewModel  │ │
│  └─────────────────────┬──────────────────────────────────┘ │
├────────────────────────┼────────────────────────────────────┤
│                   Service Layer                             │
│  ┌─────────────┐  ┌────────────┐  ┌──────────────────────┐ │
│  │ RAGEngine   │  │ LLMService │  │ EmbeddingService     │ │
│  │ (orquesta)  │  │ (Gemma 4)  │  │ (MiniLM)             │ │
│  └──────┬──────┘  └─────┬──────┘  └──────────┬───────────┘ │
│         │               │                     │             │
│  ┌──────▼───────────────▼─────────────────────▼───────────┐ │
│  │            ModelManager (singleton)                     │ │
│  │  - Gestión de RAM: carga/descarga de modelos           │ │
│  │  - Descarga desde HuggingFace Hub                      │ │
│  │  - Estado: .idle / .downloading / .ready / .error      │ │
│  └────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────┤
│                   Data Layer                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ VectorStore  │  │ ChunkStore   │  │ DocumentStore    │  │
│  │ (in-memory + │  │ (chunks de   │  │ (metadatos de    │  │
│  │  Accelerate) │  │  texto)      │  │  documentos)     │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│                         ↓                                   │
│              Persistencia: JSON en Documents/               │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Flujo de datos RAG completo

```
FASE DE INGESTA (al importar un documento):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PDF/TXT ──→ Extraer texto ──→ Chunking (~300 palabras, 50 overlap)
                                      │
              ┌───────────────────────┘
              ▼
  Cargar MiniLM en RAM (~90 MB)
              │
              ▼
  Generar embedding por chunk (384-dim Float array)
              │
              ▼
  Guardar {chunks + embeddings} en Documents/vector_store.json
              │
              ▼
  Descargar MiniLM de la RAM ← ⚠️ CRÍTICO para liberar ~90 MB


FASE DE INFERENCIA (al enviar un mensaje):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Query del usuario
              │
              ▼
  Cargar MiniLM en RAM ──→ Vectorizar query ──→ Descargar MiniLM
              │
              ▼
  Cosine Similarity (vDSP/Accelerate) contra todos los chunks
              │
              ▼
  Top-K chunks más relevantes (K=3..5)
              │
              ▼
  Construir System Prompt:
  ┌─────────────────────────────────────────────────────┐
  │ "Usa SOLO el siguiente contexto para responder:     │
  │                                                     │
  │ [Chunk 1]                                           │
  │ [Chunk 2]                                           │
  │ [Chunk 3]                                           │
  │                                                     │
  │ Si la información no está en el contexto, di que    │
  │ no tienes suficiente información."                  │
  └─────────────────────────────────────────────────────┘
              │
              ▼
  Cargar Gemma 4 E2B en RAM (~3.5-4.5 GB)
              │
              ▼
  Generar respuesta con streaming (token a token)
              │
              ▼
  Mantener Gemma 4 en RAM para siguientes mensajes
  (descargar solo si hay memory warning o si se necesita re-embeddear)
```

### 1.3 Estrategia de gestión de memoria (CRÍTICO)

**Contexto:** iPhone 15 Pro / 16 tienen 8 GB de RAM. Con el entitlement `increased-memory-limit`, una app puede usar ~5-6 GB. Gemma 4 E2B 4-bit necesita ~4-5 GB.

**Estrategia: Carga Exclusiva (Mutual Exclusion)**

```
Estado de RAM en cada momento:

[IDLE]
  → App base: ~100-150 MB
  → Disponible: ~5.5 GB

[EMBEDDING MODE]
  → App base: ~150 MB
  → MiniLM cargado: ~90-100 MB
  → Vectores en memoria: ~10-50 MB
  → Disponible: ~5.2 GB
  → ✅ Cómodo

[LLM MODE]
  → App base: ~150 MB
  → Gemma 4 E2B 4-bit: ~3.5-4.5 GB
  → KV cache (contexto): ~200-500 MB
  → Disponible: ~0.5-1.5 GB
  → ⚠️ Ajustado pero viable con contextos cortos
```

**Reglas de gestión:**

1. **Nunca** tener MiniLM y Gemma 4 cargados simultáneamente.
2. El `ModelManager` mantiene un enum de estado:
   ```
   enum ModelState {
       case idle                           // Nada cargado
       case embeddingLoaded                // MiniLM en RAM
       case llmLoaded                      // Gemma 4 en RAM
       case transitioning(from, to)        // Cambiando modelos
   }
   ```
3. Antes de cargar un modelo, descargar el otro (set referencia a `nil`, llamar `MLX.GPU.set(cacheLimit: 0)` para forzar limpieza de Metal cache).
4. Usar `os_proc_available_memory()` antes de cargar Gemma 4 para verificar que hay suficiente RAM. Si no hay suficiente, mostrar alerta al usuario.
5. Suscribirse a `UIApplication.didReceiveMemoryWarningNotification` para descargar Gemma 4 si el sistema presiona.
6. **Optimización de flujo de chat:** Una vez que la ingesta está hecha, Gemma 4 se mantiene en RAM entre mensajes. Solo se descarga si:
   - El usuario importa un nuevo documento (necesita MiniLM).
   - El sistema envía memory warning.
   - El usuario cierra la conversación.

**Entitlement obligatorio** (`Hermit.entitlements`):

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

---

## 2. Estructura de directorios del proyecto Xcode

```
Hermit/
├── Hermit.xcodeproj
├── Hermit/
│   ├── HermitApp.swift                    # @main, punto de entrada
│   ├── Info.plist                         # Configuración de la app
│   ├── Hermit.entitlements                # increased-memory-limit
│   │
│   ├── Models/                            # Modelos de datos (structs)
│   │   ├── ChatMessage.swift              # Mensaje de chat (role, content, timestamp)
│   │   ├── Document.swift                 # Metadatos de documento importado
│   │   ├── TextChunk.swift                # Chunk con texto + embedding + metadata
│   │   └── ModelInfo.swift                # Info del modelo (nombre, tamaño, estado descarga)
│   │
│   ├── Services/                          # Lógica de negocio
│   │   ├── ModelManager.swift             # Singleton: descarga, carga/descarga de modelos en RAM
│   │   ├── EmbeddingService.swift         # Genera embeddings con MiniLM via MLXEmbedders
│   │   ├── LLMService.swift               # Inferencia con Gemma 4 via mlx-swift-lm (streaming)
│   │   ├── RAGEngine.swift                # Orquesta: chunking → embedding → retrieval → generation
│   │   ├── VectorStore.swift              # Almacén de vectores in-memory + persistencia JSON
│   │   ├── DocumentProcessor.swift        # Lee PDF/TXT, extrae texto, genera chunks
│   │   └── ChunkingStrategy.swift         # Lógica de chunking (300 palabras, overlap 50)
│   │
│   ├── ViewModels/                        # @Observable ViewModels
│   │   ├── ChatViewModel.swift            # Estado del chat: mensajes, streaming, envío
│   │   ├── DocumentViewModel.swift        # Estado de documentos: importación, procesamiento
│   │   └── OnboardingViewModel.swift      # Estado de descarga inicial de modelos
│   │
│   ├── Views/                             # Vistas SwiftUI
│   │   ├── ContentView.swift              # TabView principal (Chat, Documents, Settings)
│   │   ├── Chat/
│   │   │   ├── ChatView.swift             # Vista principal del chat
│   │   │   ├── MessageBubble.swift        # Burbuja individual de mensaje
│   │   │   └── StreamingIndicator.swift   # Indicador de "pensando..." / streaming
│   │   ├── Documents/
│   │   │   ├── DocumentListView.swift     # Lista de documentos importados
│   │   │   ├── DocumentImportView.swift   # Sheet para importar PDF/TXT
│   │   │   └── DocumentDetailView.swift   # Detalle: chunks, estado de embedding
│   │   ├── Onboarding/
│   │   │   ├── OnboardingView.swift       # Pantalla de bienvenida + descarga de modelos
│   │   │   └── DownloadProgressView.swift # Barra de progreso de descarga
│   │   └── Settings/
│   │       └── SettingsView.swift         # Config: modelos descargados, uso de disco, borrar datos
│   │
│   ├── Utilities/
│   │   ├── CosineSimilarity.swift         # vDSP-based cosine similarity
│   │   └── MemoryMonitor.swift            # Wrapper sobre os_proc_available_memory()
│   │
│   └── Assets.xcassets/                   # App Icon, colores, imágenes
│       ├── AppIcon.appiconset/
│       ├── AccentColor.colorset/
│       └── Colors/                        # Paleta de colores custom
│
└── PLANNING.md                            # Este archivo
```

---

## 3. Dependencias SPM (Swift Package Manager)

### 3.1 Paquetes a añadir en Xcode

| Paquete | URL | Versión | Propósito |
|---|---|---|---|
| **mlx-swift** | `https://github.com/ml-explore/mlx-swift` | `from: "0.10.0"` | Framework de arrays MLX, backend Metal |
| **mlx-swift-lm** | `https://github.com/ml-explore/mlx-swift-lm` | `branch: "main"` | LLM inference + `MLXEmbedders` para embeddings |
| **swift-tokenizers-mlx** | `https://github.com/DePasqualeOrg/swift-tokenizers-mlx` | `from: "0.1.0"` | Adaptador de tokenizers para mlx-swift-lm v3 |
| **swift-hf-api-mlx** | `https://github.com/DePasqualeOrg/swift-hf-api-mlx` | `from: "0.1.0"` | Adaptador de HuggingFace Hub API para descargas |

> **Nota:** `mlx-swift-lm` v3 desacopló los tokenizers y el downloader en paquetes separados. Se necesitan los 4 paquetes.

### 3.2 Productos/targets a importar por archivo

| Módulo a importar | Dónde se usa |
|---|---|
| `MLX` | `ModelManager`, `MemoryMonitor` (control de GPU cache) |
| `MLXLLM` | `LLMService` (inferencia LLM, `ChatSession`, streaming) |
| `MLXEmbedders` | `EmbeddingService` (generar embeddings con MiniLM) |
| `MLXLMCommon` | `ModelManager` (tipos compartidos, `ModelContainer`) |
| `PDFKit` | `DocumentProcessor` (framework nativo de Apple, no es SPM) |
| `Accelerate` | `CosineSimilarity` (framework nativo, vDSP para similitud) |

### 3.3 Cómo añadir en Xcode (paso a paso para principiante)

1. Abrir el proyecto en Xcode.
2. Menú: **File → Add Package Dependencies...**
3. En el campo de búsqueda, pegar la URL del repositorio Git (ej: `https://github.com/ml-explore/mlx-swift`).
4. Xcode cargará el repositorio. Seleccionar la regla de versión (`Up to Next Major` o `Branch`).
5. Click **Add Package**.
6. Seleccionar los productos/targets que necesites (ej: `MLX`).
7. Repetir para cada paquete.

---

## 4. Arquitectura de gestión de estado

### 4.1 ModelManager (Singleton, corazón de la app)

```
ModelManager (@Observable, @MainActor)
├── Properties:
│   ├── modelState: ModelState              // .idle | .embeddingLoaded | .llmLoaded
│   ├── downloadState: DownloadState        // .notStarted | .downloading(progress) | .completed | .error
│   ├── embeddingModelDownloaded: Bool      // ¿Está en disco?
│   ├── llmModelDownloaded: Bool            // ¿Está en disco?
│   ├── availableMemoryMB: Int              // RAM disponible en tiempo real
│   │
│   ├── embeddingContainer: ModelContainer? // Referencia al modelo MiniLM (nil = descargado de RAM)
│   └── llmContainer: ModelContainer?       // Referencia al modelo Gemma 4 (nil = descargado de RAM)
│
├── Métodos principales:
│   ├── downloadEmbeddingModel() async      // Descarga MiniLM desde HuggingFace a Documents/
│   ├── downloadLLMModel() async            // Descarga Gemma 4 desde HuggingFace a Documents/
│   ├── loadEmbeddingModel() async throws   // Carga MiniLM en RAM (descarga LLM primero si necesario)
│   ├── loadLLM() async throws              // Carga Gemma 4 en RAM (descarga MiniLM primero si necesario)
│   ├── unloadAll()                         // Descarga todo de RAM
│   └── handleMemoryWarning()               // Suscrito a UIApplication.didReceiveMemoryWarningNotification
│
└── Lógica de transición:
    loadEmbeddingModel():
      1. if modelState == .llmLoaded → unloadLLM()
      2. MLX.GPU.set(cacheLimit: 0)
      3. Verificar os_proc_available_memory() > 200 MB
      4. Cargar modelo desde disco
      5. modelState = .embeddingLoaded

    loadLLM():
      1. if modelState == .embeddingLoaded → unloadEmbedding()
      2. MLX.GPU.set(cacheLimit: 0)
      3. Verificar os_proc_available_memory() > 4000 MB
      4. Si no hay suficiente RAM → throw InsufficientMemoryError
      5. Cargar modelo desde disco
      6. modelState = .llmLoaded
```

### 4.2 ViewModels

**ChatViewModel** (@Observable):
```
├── messages: [ChatMessage]
├── currentStreamedText: String
├── isGenerating: Bool
├── errorMessage: String?
│
├── sendMessage(text:) async
│   → Llama a RAGEngine.query(prompt:)
│   → Actualiza currentStreamedText con cada token del stream
│   → Al terminar, añade mensaje completo a messages[]
│
└── Dependencias: RAGEngine, ModelManager (observa estado)
```

**DocumentViewModel** (@Observable):
```
├── documents: [Document]
├── isProcessing: Bool
├── processingProgress: Double
├── errorMessage: String?
│
├── importDocument(url:) async
│   → DocumentProcessor.extractText(from:)
│   → ChunkingStrategy.chunk(text:)
│   → ModelManager.loadEmbeddingModel()
│   → EmbeddingService.embed(chunks:)
│   → VectorStore.save(chunks:)
│   → ModelManager.unloadAll()  // Liberar MiniLM
│
└── Dependencias: DocumentProcessor, EmbeddingService, VectorStore, ModelManager
```

**OnboardingViewModel** (@Observable):
```
├── embeddingDownloadProgress: Double
├── llmDownloadProgress: Double
├── currentStep: OnboardingStep    // .welcome | .downloading | .ready
├── errorMessage: String?
│
├── startDownloads() async
│   → ModelManager.downloadEmbeddingModel()  // ~90 MB, rápido
│   → ModelManager.downloadLLMModel()        // ~3.5 GB, lento
│
└── Dependencias: ModelManager
```

### 4.3 Inyección de dependencias

```swift
// En HermitApp.swift (@main):
@State private var modelManager = ModelManager()
@State private var vectorStore = VectorStore()
@State private var ragEngine: RAGEngine  // inicializado con las dependencias

var body: some Scene {
    WindowGroup {
        ContentView()
            .environment(modelManager)
            .environment(vectorStore)
            .environment(ragEngine)
    }
}
```

Se usa `.environment()` de SwiftUI para propagar dependencias. Los ViewModels acceden a los servicios via `@Environment`.

---

## 5. Modelos de HuggingFace

### 5.1 Modelo de embeddings

| Campo | Valor |
|---|---|
| **ID en HuggingFace** | `mlx-community/all-MiniLM-L6-v2-4bit` (o `bf16` para máxima calidad) |
| **Parámetros** | 22.7M |
| **Dimensión del embedding** | 384 |
| **Tamaño en disco** | ~23 MB (4-bit) / ~90 MB (bf16) |
| **RAM en uso** | ~30-100 MB |
| **Formato** | MLX safetensors |

> **Recomendación:** Usar la versión `bf16` (90 MB). MiniLM es tan pequeño que la cuantización no ahorra RAM relevante y puede degradar la calidad de los embeddings.

### 5.2 Modelo LLM

| Campo | Valor |
|---|---|
| **ID en HuggingFace** | `mlx-community/gemma-4-e2b-it-4bit` |
| **Parámetros totales** | ~5.1B (2.3B activos, PLE embeddings) |
| **Tamaño en disco** | ~3.58 GB |
| **RAM estimada (inference)** | ~4-5 GB (pesos + KV cache) |
| **Formato** | MLX safetensors, 4-bit quantization |
| **Contexto máximo** | 128K tokens (limitar a ~2K-4K en iPhone) |
| **Capacidades** | Texto (usamos solo texto; también soporta imagen/audio/video) |

> **Alternativa más ligera:** `unsloth/gemma-4-E2B-it-UD-MLX-4bit` con cuantización dinámica (~1.5-3 GB). Considerar si Gemma 4 estándar causa OOM en el dispositivo target.

### 5.3 Directorio de almacenamiento en el dispositivo

```
Documents/
├── models/
│   ├── embeddings/
│   │   └── all-MiniLM-L6-v2-bf16/     # Archivos descargados de HF
│   │       ├── config.json
│   │       ├── model.safetensors
│   │       ├── tokenizer.json
│   │       └── tokenizer_config.json
│   └── llm/
│       └── gemma-4-e2b-it-4bit/        # Archivos descargados de HF
│           ├── config.json
│           ├── model-00001-of-00002.safetensors
│           ├── model-00002-of-00002.safetensors
│           ├── tokenizer.json
│           └── tokenizer_config.json
├── vector_store/
│   └── {document_id}.json              # Chunks + embeddings por documento
└── documents/
    └── metadata.json                   # Lista de documentos importados
```

---

## 6. Plan de implementación (4 Fases)

### Fase 1: Setup del proyecto y UI base (~2 días)

**Objetivo:** Proyecto Xcode funcional con navegación, vistas placeholder, y sistema de theming.

#### Tareas:

- [ ] **1.1** Crear proyecto Xcode nuevo:
  - File → New → Project → App
  - Interface: SwiftUI
  - Language: Swift
  - Nombre: `Hermit`
  - Bundle ID: `com.hermit.app` (o el que prefieras)
  - Minimum Deployment: **iOS 18.0** (requerido por MLX)

- [ ] **1.2** Configurar entitlements:
  - Añadir `Hermit.entitlements` al target
  - Añadir `com.apple.developer.kernel.increased-memory-limit = true`

- [ ] **1.3** Crear estructura de carpetas (Models/, Services/, ViewModels/, Views/, Utilities/)

- [ ] **1.4** Añadir dependencias SPM:
  - `mlx-swift` (from: 0.10.0)
  - `mlx-swift-lm` (branch: main)
  - `swift-tokenizers-mlx` (from: 0.1.0)
  - `swift-hf-api-mlx` (from: 0.1.0)
  - Verificar que compila sin errores (`Cmd+B`)

- [ ] **1.5** Implementar modelos de datos:
  - `ChatMessage.swift`: id, role (user/assistant/system), content, timestamp
  - `Document.swift`: id, name, url, dateAdded, chunkCount, isProcessed
  - `TextChunk.swift`: id, documentId, text, embedding ([Float]), pageNumber, chunkIndex
  - `ModelInfo.swift`: id, name, huggingFaceId, sizeOnDisk, isDownloaded

- [ ] **1.6** Implementar UI base:
  - `ContentView.swift`: TabView con 3 tabs (Chat, Documents, Settings)
  - `ChatView.swift`: Lista de mensajes + campo de texto + botón enviar
  - `MessageBubble.swift`: Burbuja estilizada (usuario: derecha/azul, assistant: izquierda/gris)
  - `DocumentListView.swift`: Lista vacía con botón "+" para importar
  - `SettingsView.swift`: Info de modelos, uso de disco, versión de la app
  - `OnboardingView.swift`: Pantalla de bienvenida (se mostrará si los modelos no están descargados)

- [ ] **1.7** Diseño visual:
  - Paleta de colores en `Assets.xcassets` (dark mode compatible)
  - Estilo minimalista: fondos oscuros, acentos cálidos (ámbar/dorado para "Hermit")
  - Tipografía: San Francisco (sistema) con variaciones de peso
  - Animaciones sutiles en la aparición de mensajes
  - App Icon diseñado (un cangrejo ermitaño estilizado o similar)

**Resultado:** App que compila y navega entre vistas, sin funcionalidad de IA aún.

---

### Fase 2: Gestor de descargas de modelos (~2 días)

**Objetivo:** Descargar modelos de HuggingFace al dispositivo y mostrar progreso.

#### Tareas:

- [ ] **2.1** Implementar `ModelManager.swift`:
  - Singleton `@Observable`
  - Propiedades de estado: `modelState`, `downloadState`, `availableMemoryMB`
  - Método `downloadModel(id:to:)` usando la API de `mlx-swift-lm` (que internamente usa `swift-hf-api-mlx` para descargar desde HuggingFace Hub)
  - Progreso de descarga vía callback/AsyncStream
  - Verificar si los modelos ya existen en disco al inicializar
  - Calcular espacio en disco disponible antes de descargar

- [ ] **2.2** Implementar `MemoryMonitor.swift`:
  - Wrapper sobre `os_proc_available_memory()`
  - Timer que actualiza `availableMemoryMB` cada 2 segundos
  - Método `hasEnoughMemory(forModel:) -> Bool`
  - Suscripción a `UIApplication.didReceiveMemoryWarningNotification`

- [ ] **2.3** Implementar `OnboardingViewModel.swift`:
  - Orquestar la descarga secuencial: primero MiniLM (~90 MB, ~30s), luego Gemma 4 (~3.5 GB, ~10-30 min en Wi-Fi)
  - Manejo de errores: red caída, disco lleno, descarga interrumpida
  - Persistir estado de descarga para reanudar si la app se cierra

- [ ] **2.4** Implementar UI de onboarding:
  - `OnboardingView.swift`:
    - Paso 1: Pantalla de bienvenida con explicación de privacidad
    - Paso 2: Descarga de modelos con barras de progreso
    - Paso 3: "Listo para usar"
  - `DownloadProgressView.swift`: Barra de progreso animada con MB descargados / MB totales
  - Mostrar estimación de espacio necesario (~3.7 GB total)
  - Botón para cancelar/reintentar

- [ ] **2.5** Actualizar `SettingsView.swift`:
  - Mostrar modelos descargados, espacio ocupado
  - Botón para borrar modelos y re-descargar
  - Indicador de RAM disponible en tiempo real

**Resultado:** Al abrir la app por primera vez, se descargan los modelos. En posteriores aperturas, se detecta que ya están en disco.

---

### Fase 3: Motor de embeddings y pipeline RAG (~3 días)

**Objetivo:** Importar documentos, generar embeddings, almacenar vectores, y recuperar chunks relevantes.

#### Tareas:

- [ ] **3.1** Implementar `DocumentProcessor.swift`:
  - `extractText(from url: URL) -> String`:
    - Si es `.txt`: `String(contentsOf:encoding:)`
    - Si es `.pdf`: `PDFDocument(url:)` → iterar páginas → `page.string`
  - Manejo de PDFs escaneados: detectar si `page.string` está vacío y mostrar error claro ("Este PDF no contiene texto extraíble")

- [ ] **3.2** Implementar `ChunkingStrategy.swift`:
  - `chunk(text:targetWords:overlapWords:) -> [String]`
  - Algoritmo recursivo:
    1. Dividir por párrafos (doble salto de línea)
    2. Si un párrafo excede `targetWords`, dividir por oraciones
    3. Si una oración excede `targetWords`, dividir por palabras
    4. Agrupar fragmentos hasta alcanzar ~300 palabras
    5. Overlap de ~50 palabras entre chunks consecutivos
  - Preservar metadata: índice del chunk, posición en el texto original

- [ ] **3.3** Implementar `EmbeddingService.swift`:
  - `loadModel() async throws` → Usa `MLXEmbedders` para cargar `all-MiniLM-L6-v2` desde disco
  - `embed(text: String) async throws -> [Float]` → Genera embedding de 384 dimensiones
  - `embed(chunks: [String]) async throws -> [[Float]]` → Batch processing
  - `unloadModel()` → Set referencia a nil, limpiar GPU cache
  - Coordinar con `ModelManager` para transiciones de estado

- [ ] **3.4** Implementar `VectorStore.swift`:
  - Almacenamiento in-memory: `[TextChunk]` con embeddings `[Float]`
  - `save(chunks:forDocument:)` → Serializar a JSON en `Documents/vector_store/`
  - `loadAll()` → Deserializar todos los JSON al iniciar la app
  - `search(query: [Float], topK: Int) -> [TextChunk]` → Cosine similarity
  - `delete(documentId:)` → Eliminar chunks de un documento

- [ ] **3.5** Implementar `CosineSimilarity.swift`:
  - Usar `Accelerate` framework (vDSP):
    ```
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float
      → vDSP.dot(a, b) / (sqrt(vDSP.sumOfSquares(a)) * sqrt(vDSP.sumOfSquares(b)))
    ```
  - Función de búsqueda batch: comparar query contra N vectores, retornar top-K

- [ ] **3.6** Implementar `RAGEngine.swift`:
  - `ingestDocument(url:) async throws`:
    1. Extraer texto → Chunking → Load MiniLM → Embed chunks → Save → Unload MiniLM
  - `retrieveContext(for query: String, topK: Int) async throws -> [TextChunk]`:
    1. Load MiniLM → Embed query → Cosine search → Unload MiniLM → Return top-K
  - Orquestar transiciones de modelos via `ModelManager`

- [ ] **3.7** Implementar `DocumentViewModel.swift`:
  - Estado de importación: selección de archivo → procesamiento → embedding → completado
  - Usar `fileImporter` modifier de SwiftUI para seleccionar PDF/TXT
  - Mostrar progreso: "Extrayendo texto..." → "Generando embeddings (3/15 chunks)..." → "Completado"

- [ ] **3.8** Actualizar UI de documentos:
  - `DocumentImportView.swift`: Sheet con file picker y progreso
  - `DocumentListView.swift`: Lista con nombre, fecha, nº de chunks, swipe-to-delete
  - `DocumentDetailView.swift`: Preview de chunks, estadísticas

**Resultado:** Se puede importar un PDF/TXT, ver los chunks generados, y los embeddings están almacenados y listos para búsqueda.

---

### Fase 4: Inferencia LLM con streaming (~3 días)

**Objetivo:** Chat funcional con Gemma 4 E2B usando contexto RAG y respuestas en streaming.

#### Tareas:

- [ ] **4.1** Implementar `LLMService.swift`:
  - `loadModel() async throws`:
    - Coordinar con `ModelManager` (descargar embedding model si está cargado)
    - Cargar Gemma 4 desde disco usando `MLXLLM` / `ModelContainer`
    - Crear `ChatSession` para mantener contexto de conversación
  - `generate(systemPrompt:userMessage:) -> AsyncThrowingStream<String, Error>`:
    - Construir el prompt con el system prompt (contexto RAG inyectado)
    - Usar `ChatSession.streamResponse(to:)` para streaming token a token
  - `unloadModel()`:
    - Set `ChatSession` y `ModelContainer` a nil
    - `MLX.GPU.set(cacheLimit: 0)`
  - `resetConversation()`:
    - Crear nueva `ChatSession` manteniendo el modelo cargado

- [ ] **4.2** Completar `RAGEngine.query()`:
  - `query(prompt: String) -> AsyncThrowingStream<String, Error>`:
    1. Recuperar contexto: `retrieveContext(for: prompt, topK: 3)`
    2. Construir system prompt con chunks inyectados
    3. Descargar MiniLM, cargar Gemma 4
    4. `LLMService.generate(systemPrompt:userMessage:)`
    5. Retornar el stream de tokens

- [ ] **4.3** Implementar `ChatViewModel.swift`:
  - `sendMessage(text:)`:
    1. Añadir mensaje del usuario a `messages[]`
    2. `isGenerating = true`
    3. Iterar sobre el stream de `RAGEngine.query()`
    4. Actualizar `currentStreamedText` con cada token (UI se actualiza en tiempo real)
    5. Al terminar, añadir mensaje completo del assistant a `messages[]`
    6. `isGenerating = false`
  - Manejo de errores: OOM, modelo no disponible, generación cancelada
  - Cancelación: botón "Stop" que cancela el Task de generación

- [ ] **4.4** Actualizar UI del chat:
  - `ChatView.swift`:
    - ScrollView con mensajes (scroll automático al último mensaje)
    - Campo de texto con botón de envío
    - Deshabilitado si no hay documentos importados o modelos no descargados
    - Indicador de estado: "Cargando modelo..." / "Buscando contexto..." / "Generando..."
  - `MessageBubble.swift`:
    - Animación de aparición de texto durante streaming (efecto typewriter)
    - Markdown rendering básico en las respuestas
    - Timestamp discreto
  - `StreamingIndicator.swift`:
    - Animación de puntos pulsantes mientras genera
    - Botón "Detener generación"

- [ ] **4.5** System Prompt template:
  ```
  Eres un asistente que responde preguntas basándose EXCLUSIVAMENTE en el
  contexto proporcionado. No inventes información.

  CONTEXTO:
  ---
  {chunk_1}
  ---
  {chunk_2}
  ---
  {chunk_3}
  ---

  REGLAS:
  - Responde SOLO con información del contexto anterior.
  - Si la respuesta no está en el contexto, di: "No encuentro esa información
    en los documentos proporcionados."
  - Cita la parte relevante del contexto cuando sea posible.
  - Responde en el mismo idioma que el usuario.
  ```

- [ ] **4.6** Testing end-to-end:
  - Probar con un PDF de ~10 páginas
  - Verificar que la ingesta funciona (chunks + embeddings generados)
  - Verificar que el retrieval encuentra chunks relevantes
  - Verificar que Gemma 4 genera respuestas coherentes con streaming
  - Verificar gestión de memoria (no OOM)
  - Probar memory warning handling
  - Probar en iPhone real (no solo simulador, ya que el simulador no tiene limitaciones de RAM reales)

- [ ] **4.7** Pulir UX:
  - Onboarding flow completo (primera apertura → descarga → primer documento → primer chat)
  - Empty states con ilustraciones/mensajes guía
  - Haptic feedback en acciones clave
  - Transiciones suaves entre estados de carga de modelos
  - Indicador en SettingsView de RAM usada por el modelo actual

**Resultado:** App completa MVP. El usuario puede importar un documento, hacer preguntas sobre su contenido, y recibir respuestas generadas por Gemma 4 con contexto RAG.

---

## 7. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| **OOM en iPhone 8GB con Gemma 4** | Alta | Crítico | Usar `os_proc_available_memory()` antes de cargar. Ofrecer alternativa con modelo Unsloth más ligero (~1.5 GB). Limitar contexto a ~2K tokens. |
| **Descarga de 3.5 GB interrumpida** | Media | Alto | Implementar descarga resumible (si la API de HF lo soporta). Persistir estado de descarga. Reintentar automáticamente. |
| **mlx-swift-lm API cambia (branch: main)** | Media | Medio | Pinear a un commit específico cuando el desarrollo sea estable. Monitorear releases. |
| **Calidad de embeddings insuficiente** | Baja | Medio | Probar con `bf16` en vez de `4bit` para MiniLM. Si no mejora, evaluar modelos más grandes (bge-small, nomic-embed-text). |
| **Rendimiento de inferencia lento en iPhone** | Media | Medio | Aceptable para MVP (~5-15 tokens/seg en iPhone 15 Pro). Optimizar limitando max_tokens de respuesta. |
| **Thermal throttling sostenido** | Media | Bajo | Informar al usuario. Reducir max_tokens si la generación es muy larga. |

---

## 8. Limitaciones conocidas de MLX en iOS

1. **No usa el Neural Engine (ANE).** MLX ejecuta en GPU via Metal. El ANE solo es accesible via CoreML y no soporta bien la generación autoregresiva de tokens.
2. **Sin Metal 4 / TensorOps en iPhone.** Las aceleraciones de Neural Accelerators del M5 (4x en MatMul) solo están disponibles en Mac, no en chips A-series de iPhone.
3. **Los shaders Metal no se compilan via SPM CLI.** Se debe compilar siempre desde Xcode o `xcodebuild`, nunca `swift build` desde terminal.
4. **Context length limitado por RAM.** Aunque Gemma 4 soporta 128K tokens, en iPhone el KV cache crece linealmente con el contexto. Mantener bajo ~2K-4K tokens es prudente.
5. **Framework orientado a investigación.** MLX no está optimizado para producción móvil al nivel de CoreML. Para una app de producción a largo plazo, considerar migrar a CoreML o al Foundation Models framework de Apple (cuando soporte modelos custom).

---

## 9. Decisiones de diseño UI

### Paleta de colores (dark-first)

```
Background principal:    #0F0F0F (casi negro)
Background secundario:   #1A1A1A (cards, burbujas assistant)
Acento principal:        #F5A623 (ámbar/dorado - "hermit crab")
Acento secundario:       #E8D5B7 (beige cálido)
Texto principal:         #FAFAFA
Texto secundario:        #8E8E93
Burbuja usuario:         #2C5F2D (verde oscuro)
Error:                   #FF453A
Éxito:                   #30D158
```

### Tipografía

- Títulos: SF Pro Display, Bold
- Body: SF Pro Text, Regular
- Código/chunks: SF Mono, Regular
- Tamaños: Dynamic Type compatible (accesibilidad)

### Principios de diseño

- **Privacy-first visual:** Icono de candado sutil en la barra superior. Badge "100% On-Device" visible.
- **Estado del modelo siempre visible:** Pequeño indicador en la tab bar o header que muestra qué modelo está en RAM.
- **Progressive disclosure:** No abrumar al usuario. Onboarding paso a paso. El chat no se habilita hasta que hay al menos un documento importado.
- **Feedback constante:** Toda operación larga (descarga, embedding, generación) tiene indicador de progreso visible.

---

## 10. Comandos útiles durante el desarrollo

```bash
# Compilar desde terminal (útil para CI, pero no compila shaders Metal)
xcodebuild -scheme Hermit -destination 'platform=iOS,name=iPhone de [tu nombre]' build

# Limpiar caché de SPM si hay problemas de dependencias
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build

# Ver logs del dispositivo en tiempo real (útil para debug de memory warnings)
xcrun simctl spawn booted log stream --level debug --predicate 'process == "Hermit"'

# Ver memoria del proceso en un iPhone conectado
xcrun devicectl device info processes --device [UDID] | grep Hermit

# Profiling de memoria con Instruments
# Xcode → Product → Profile → Allocations / Leaks
```

---

## Checklist pre-desarrollo

- [ ] Mac con Apple Silicon y macOS Sequoia 15.6+ o Tahoe 26.2+
- [ ] Xcode instalado y verificado (`xcodebuild -version`)
- [ ] Apple Account creada (gratuita suficiente)
- [ ] iPhone 15 Pro o posterior disponible para testing
- [ ] Al menos 40 GB libres en Mac (Xcode + caché)
- [ ] Al menos 5 GB libres en iPhone (para modelos descargados)
- [ ] Wi-Fi estable (para descargar ~3.7 GB de modelos durante desarrollo)
