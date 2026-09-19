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

Run beside the MLX resource bundle. Keep GPU workloads sequential. The `legacy` embedding arm preserves serialized tokenizer truncation/padding and old pooling; `legacy_full` removes truncation/padding but keeps word chunks and old pooling; `tokenizer_only` adds 256/32 token chunks while retaining old pooling. Numeric candidates use the final app pipeline.

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

From the repository, score retrieval, generate matched answer inputs, then score the outputs. The answer scorer reports normalized exact match and token-overlap F1: lowercase, remove Unicode punctuation, remove the English/Spanish articles explicitly listed in `analyze.py`, and maximize over annotated gold answers. It is not a semantic judge or a production success metric.

```bash
VECLIB_MAXIMUM_THREADS=1 OPENBLAS_NUM_THREADS=1 uv run --no-project --with numpy==2.4.3 \
  python benchmarks/analyze.py "$HERMIT_BENCH_ROOT/data"
cd "$HERMIT_BENCH_ROOT/build/Build/Products/Release"
./HermitBench answers "$HERMIT_BENCH_ROOT/models/gemma" "$HERMIT_BENCH_ROOT/data/answer-cases.json" "$HERMIT_BENCH_ROOT/data/answers.json"
# Return to the repository and repeat analyze.py to write answer-summary.json.
```

For cache comparisons, invoke `HermitBench gemma upstream MODEL PROMPT IMAGE_OR_DASH OUTPUT.json` with default environment (0/32/64 MiB, one warm-up each, five interleaved repeats). Exact text/photo prompts are retained in the reference `cache-text.json` and `cache-photo.json`. Each request starts with an empty allocation cache and a fresh conversation; weights stay loaded. Report only repetitions 0–4. These runs measure cache reuse within a request, not retained allocation reuse between requests. Preprocessing is separately timed and synchronized; generation prepares its own input again. The preprocessing probe can warm GPU kernels. No operating-system page cache was flushed, so these are warm workload comparisons, not cold-start benchmarks.

The Gemma legacy command is the same with `legacy` instead of `upstream`. Its recorded load failure is a result; do not modify its weights/model to manufacture a quality comparison. The old full package stack and the original iOS binary are outside that controlled comparison.

Raw vector files are regeneration intermediates and are not committed. The reference summaries, per-query ranks, outputs, provenance, and source hashes are retained in `results/2026-09-19/`. Compare the recorded input hashes before treating a rerun as identical. The MLQA development corpus is [Facebook Research MLQA](https://github.com/facebookresearch/MLQA), CC BY-SA 3.0; its Wikipedia passages and annotations remain external inputs. No user documents are used.
