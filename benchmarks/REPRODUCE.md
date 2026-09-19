# Reproduce the native validation

Use an Apple Silicon Mac with Xcode 26.4, XcodeGen, Python 3, and `uv`. This is a separate command-line target: none of these benchmark sources is part of the iOS app. The historical source is extracted unchanged from `dd98f8e`; only a protocol-forwarding bridge adapts it to the current runtime. `prepare.py` compiles the current app chunker, embedding function, and `LLMService` rather than copying their algorithms.

The reference run used M3 Pro / 36 GiB, macOS 26.6.1. Dependencies come from `project.yml` and the app lockfile. Downloads are public; inference uses no paid API. Allow approximately 4 GB for input files plus Xcode build products. Original inputs are preserved; all generated files go under the scratch root.

```bash
export HERMIT_BENCH_ROOT=/tmp/hermit-bench
mkdir -p "$HERMIT_BENCH_ROOT/data"
uvx --from huggingface_hub hf download mlx-community/gemma-4-e2b-it-4bit \
  model.safetensors model.safetensors.index.json config.json generation_config.json \
  processor_config.json tokenizer.json tokenizer_config.json chat_template.jinja \
  --revision 238767527555cb75a05732a84dff5d6ba0dd6809 --local-dir "$HERMIT_BENCH_ROOT/models/gemma"
uvx --from huggingface_hub hf download mlx-community/all-MiniLM-L6-v2-bf16 \
  model.safetensors model.safetensors.index.json config.json modules.json \
  tokenizer.json tokenizer_config.json special_tokens_map.json vocab.txt \
  sentence_bert_config.json config_sentence_transformers.json data_config.json \
  --revision b6691709eacd8f0afcc3faace288cf50e611f3aa --local-dir "$HERMIT_BENCH_ROOT/models/minilm"
curl -fL https://dl.fbaipublicfiles.com/MLQA/MLQA_V1.zip -o "$HERMIT_BENCH_ROOT/data/MLQA_V1.zip"
curl -fL https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/coco_sample.png \
  -o "$HERMIT_BENCH_ROOT/data/cats.png"
python3 benchmarks/prepare.py "$HERMIT_BENCH_ROOT"
xcodegen generate --spec "$HERMIT_BENCH_ROOT/project.yml" --project "$HERMIT_BENCH_ROOT"
xcodebuild -resolvePackageDependencies -project "$HERMIT_BENCH_ROOT/HermitBench.xcodeproj" -scheme HermitBench
xcodebuild -project "$HERMIT_BENCH_ROOT/HermitBench.xcodeproj" -scheme HermitBench \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$HERMIT_BENCH_ROOT/build" build
```

Run beside the MLX resource bundle. Keep GPU workloads sequential. The `legacy` embedding arm uses the new runtime/tokenizer with serialized truncation/padding and old pooling; it is not the original locked-stack baseline. `legacy_full` removes truncation/padding but keeps word chunks and old pooling; `tokenizer_only` adds 256/32 token chunks while retaining old pooling. Numeric candidates use the final app pipeline.

```bash
cd "$HERMIT_BENCH_ROOT/build/Build/Products/Release"
for arm in legacy legacy_full tokenizer_only 128_0 128_32 192_0 192_32 256_0 256_32; do
  ./HermitBench embeddings "$HERMIT_BENCH_ROOT/models/minilm" "$HERMIT_BENCH_ROOT/data/corpus.json" \
    "$arm" "$HERMIT_BENCH_ROOT/data/corrected-$arm.json"
done
./HermitBench batches "$HERMIT_BENCH_ROOT/models/minilm" "$HERMIT_BENCH_ROOT/data/corpus.json" "$HERMIT_BENCH_ROOT/data/batches.json"
./HermitBench search "$HERMIT_BENCH_ROOT/data/search.json"
./HermitBench sessions "$HERMIT_BENCH_ROOT/models/gemma" "$HERMIT_BENCH_ROOT/data/sessions.json" "$HERMIT_BENCH_ROOT/data/cats.png"
./HermitBench fixtures "$HERMIT_BENCH_ROOT/data"
for shape in square portrait landscape; do
  HERMIT_BENCH_REPEATS=0 HERMIT_BENCH_CACHE_MB=0 ./HermitBench gemma upstream "$HERMIT_BENCH_ROOT/models/gemma" \
    'List each shape and its color, then transcribe the black text exactly.' \
    "$HERMIT_BENCH_ROOT/data/$shape.png" "$HERMIT_BENCH_ROOT/data/vision-$shape.json"
done
```

Before scoring, also run the original locked stack. The snapshot in `original-stack/Package.resolved` came from the original local checkout, where the lockfile was ignored by Git. The harness uses unchanged model/chunker sources from `dd98f8e` and the original embedding call. Its >512-token whole-document guard is a benchmark safety measure absent from the old app. Preserve the branch declaration required by the old adapters, and disable automatic resolution so the saved revision is used.

```bash
# Run from the repository root.
export HERMIT_ORIGINAL_ROOT=/tmp/hermit-original-stack
mkdir -p "$HERMIT_ORIGINAL_ROOT/Sources" "$HERMIT_ORIGINAL_ROOT/HermitOriginal.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
cp benchmarks/original-stack/Run.swift "$HERMIT_ORIGINAL_ROOT/Sources/Run.swift"
cp benchmarks/original-stack/project.yml "$HERMIT_ORIGINAL_ROOT/project.yml"
cp benchmarks/original-stack/Package.resolved "$HERMIT_ORIGINAL_ROOT/HermitOriginal.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
for name in Gemma4Text Gemma4Vision Gemma4VLM ChunkingStrategy; do
  git show "dd98f8e:Hermit/Services/$name.swift" > "$HERMIT_ORIGINAL_ROOT/Sources/$name.swift"
done
xcodegen generate --spec "$HERMIT_ORIGINAL_ROOT/project.yml" --project "$HERMIT_ORIGINAL_ROOT"
xcodebuild -project "$HERMIT_ORIGINAL_ROOT/HermitOriginal.xcodeproj" -scheme HermitOriginal \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$HERMIT_ORIGINAL_ROOT/build" -disableAutomaticPackageResolution -skipPackageUpdates build
cd "$HERMIT_ORIGINAL_ROOT/build/Build/Products/Release"
./HermitOriginal embeddings "$HERMIT_BENCH_ROOT/models/minilm" "$HERMIT_BENCH_ROOT/data/corpus.json" \
  "$HERMIT_BENCH_ROOT/data/corrected-original_stack.json"
./HermitOriginal gemma "$HERMIT_BENCH_ROOT/models/gemma" "$HERMIT_BENCH_ROOT/data/original-stack-gemma.txt"
```

From the repository, score retrieval, generate matched answer inputs, then score the outputs. The 160-answer pilot uses only new-stack retrieval/generation arms, not original-stack generation. The answer scorer reports normalized exact match and token-overlap F1: lowercase, remove Unicode punctuation, remove the English/Spanish articles explicitly listed in `analyze.py`, and maximize over annotated gold answers. It is not a semantic judge or a production success metric.

```bash
VECLIB_MAXIMUM_THREADS=1 OPENBLAS_NUM_THREADS=1 uv run --no-project --with numpy==2.4.3 \
  python benchmarks/analyze.py "$HERMIT_BENCH_ROOT/data"
cd "$HERMIT_BENCH_ROOT/build/Build/Products/Release"
./HermitBench answers "$HERMIT_BENCH_ROOT/models/gemma" "$HERMIT_BENCH_ROOT/data/answer-cases.json" "$HERMIT_BENCH_ROOT/data/answers.json"
# Return to the repository and repeat analyze.py to write answer-summary.json.
```

For cache comparisons, invoke `HermitBench gemma upstream MODEL PROMPT IMAGE_OR_DASH OUTPUT.json` with default environment (0/32/64 MiB, one warm-up each, five interleaved repeats). Exact text/photo prompts are retained in the reference `cache-text.json` and `cache-photo.json`. Each request starts with an empty allocation cache and a fresh conversation; weights stay loaded. Report only repetitions 0–4. These runs measure cache reuse within a request, not retained allocation reuse between requests. Preprocessing is separately timed and synchronized; generation prepares its own input again. The preprocessing probe can warm GPU kernels. No operating-system page cache was flushed, so these are warm workload comparisons, not cold-start benchmarks.

The Gemma legacy command is the same with `legacy` instead of `upstream`. Its recorded load failure is a result; do not modify its weights/model to manufacture a quality comparison. The separate original-stack harness also fails loading the same checkpoint. No original iOS binary or older working checkpoint is compared.

Raw vector files are regeneration intermediates and are not committed. The reference summaries, per-query ranks, outputs, provenance, and source hashes are retained in `results/2026-09-19/`. Compare the recorded input hashes before treating a rerun as identical. The MLQA development corpus is [Facebook Research MLQA](https://github.com/facebookresearch/MLQA), CC BY-SA 3.0; its Wikipedia passages and annotations remain external inputs. No user documents are used.

## Physical iPhone validation

The connected device selected by the user is an **iPhone 16 Pro**, replacing the initial iPhone 15 Pro target. Use a separate validation bundle identifier to preserve installed app data and avoid changing the repository's identifier. Xcode must be signed in; pair/unlock the phone, enable Developer Mode, and trust the development certificate under Settings → General → VPN & Device Management. Use your own team and bundle identifiers below. The reference profile includes the increased-memory-limit entitlement.

```bash
export HERMIT_DEVICE_ROOT=/tmp/hermit-device-project
export HERMIT_DEVICE_BUILD=/tmp/hermit-device-validation
# Set HERMIT_DEVICE_ID (UDID), HERMIT_TEAM_ID, and HERMIT_BUNDLE_ID for your device/team.
python3 benchmarks/prepare_device.py "$HERMIT_DEVICE_ROOT" "$HERMIT_BUNDLE_ID" "$HERMIT_BENCH_ROOT/data"
xcodegen generate --spec "$HERMIT_DEVICE_ROOT/project.yml" --project "$HERMIT_DEVICE_ROOT"
xcodebuild -project "$HERMIT_DEVICE_ROOT/Hermit.xcodeproj" -scheme Hermit -configuration Release \
  -destination "platform=iOS,id=$HERMIT_DEVICE_ID" -derivedDataPath "$HERMIT_DEVICE_BUILD" \
  -disableAutomaticPackageResolution -skipPackageUpdates DEVELOPMENT_TEAM="$HERMIT_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES -allowProvisioningUpdates -allowProvisioningDeviceRegistration build-for-testing
xcrun devicectl device install app --device "$HERMIT_DEVICE_ID" "$HERMIT_DEVICE_BUILD/Build/Products/Release-iphoneos/Hermit.app"
xcrun devicectl device copy to --device "$HERMIT_DEVICE_ID" --source "$HERMIT_DEVICE_ROOT/model-cache" \
  --destination Library/Caches/huggingface/hub --domain-type appDataContainer --domain-identifier "$HERMIT_BUNDLE_ID"
xcrun devicectl device copy to --device "$HERMIT_DEVICE_ID" --source "$HERMIT_DEVICE_ROOT/hermit-benchmark-inputs.json" \
  --destination Documents/hermit-benchmark-inputs.json --domain-type appDataContainer --domain-identifier "$HERMIT_BUNDLE_ID"
xcrun devicectl device copy to --device "$HERMIT_DEVICE_ID" --source "$HERMIT_BENCH_ROOT/data/cats.png" \
  --destination Documents/hermit-cats.png --domain-type appDataContainer --domain-identifier "$HERMIT_BUNDLE_ID"
```

The preparation script stages the pinned model files from `$HERMIT_BENCH_ROOT/models`, reusing hard links when possible, and fetches their public repository metadata. It writes `refs/main` and the `.metadata/models--mlx-community--MODEL/REVISION.json` file required by HubClient's snapshot verification, checking local file sizes against the pinned repository metadata. Copy the entire staged cache, including `.metadata`; copying only snapshots/refs makes the app report models as unavailable. No credentials are copied. This bypasses network downloading in the app, so it is not a validation of the onboarding download flow.

In a copy of the generated `.xctestrun` next to the original, set `HERMIT_MODEL_TESTS=1` and `HERMIT_DEVICE_BENCHMARKS=1` in each `TestConfigurations[].TestTargets[].EnvironmentVariables`, and `ParallelizationEnabled=false`. Keep `__TESTROOT__` paths intact. Run the suites **sequentially**, because separate test suites would otherwise create independent model managers. Ordinary view-model tests assume no downloaded models and must not run alongside these GPU suites.

```bash
for suite in EmbeddingServiceIntegrationTests LLMServiceIntegrationTests DevicePerformanceTests; do
  xcodebuild test-without-building -xctestrun "$HERMIT_DEVICE_BUILD/Build/Products/Hermit-models.xctestrun" \
    -destination "platform=iOS,id=$HERMIT_DEVICE_ID" -parallel-testing-enabled NO -collect-test-diagnostics never \
    -only-testing:"HermitTests/$suite" -resultBundlePath "$HERMIT_DEVICE_ROOT/$suite.xcresult"
done
```

Use fresh result-bundle paths for reruns. Copy `Documents/hermit-device-cache.json`, `hermit-device-batches.json`, and `hermit-device-runtime.json` back with `devicectl device copy from`. The cache sweep uses the same prompts, temperature 0, 128-token cap, and preprocessing probe as the Mac harness. It interleaves text/photo and 0/32/64 MiB caches for one warm-up and five measured repetitions, with a fresh session per request. The batch sweep uses the same 32 passages/32 queries, but measures the actual app service including model load/unload on every call; its timings are not equivalent to the Mac kernel-only measurements. Record thermal state and output/token changes before choosing defaults. Footprint is sampled after each request, not a peak process-footprint measurement; MLX peak allocation is separately recorded. MainActor scheduling gaps are a responsiveness probe, not rendered frame times or a full UI audit. Injected memory-warning notifications verify the app's handler during GPU generation, not survival of real OS memory pressure.
