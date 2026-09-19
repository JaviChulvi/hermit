# Hermit performance validation

The [completed Mac results](RESULTS.md) and [reproduction commands](REPRODUCE.md) supersede the pending entries in the historical plan below. Physical-device gates remain open.

## Plan recorded before measurement (2026-09-19)

Target: balanced speed, memory, and answer quality on iPhone 15 Pro / 8 GB. The paired phone is unavailable. This first stage uses an Apple M3 Pro Mac with 36 GiB RAM, macOS 26.6.1, Xcode 26.4, and the PR's pinned Swift packages. Mac results cannot select phone memory/cache defaults or verify iOS lifecycle/thermal behavior.

Controls and scope:

- Gemma: compare the custom model/processor from commit `dd98f8e` with upstream 3.31.4, on the **same current MLX runtime**, same model revision, temperature 0, and output budget. This isolates model/processor compatibility, not the full old dependency stack. Include EN/ES answers and square/portrait/landscape fixtures with predefined ground truth. Save actual outputs, prompt counts, and processed image dimensions.
- Cache: compare 0/32/64 MiB after independent warm-up, interleaving five repeats. Synchronize completion and reset MLX peak counters. Report preprocessing, prefill, decode, token counts, median/range and peak allocation separately for text/photo. Five repeats do not establish a stable p95. Keep phone cache=0 pending device results.
- Embeddings: use the deployed MiniLM revision, unchanged normalization/layer norm, and the app's exact batch implementation. Compare batches 1/4/8 for throughput, peak allocation, vector cosine agreement and retrieval ranking. Keep phone batch=1 pending device results.
- Retrieval: real Wikipedia paragraphs/questions from [MLQA development data](https://github.com/facebookresearch/MLQA), independently scored for English and Spanish. Deterministic seed 20260919; tuning/evaluation split by source article. The indexed passage corpus excludes question text. Record length distributions and source/answer-span containment; an answer string in another article does not count. This is a screening corpus, not user-document or production-quality evidence.
- Chunk candidates: original 300-word/50-word overlap versus token budgets 128/192/256 with overlap 0/32. Run original chunks above the documented 256-token policy when they fit the model's actual positional capacity; report capacity violations as whole-document ingestion failures. Never silently truncate the control.
- Search: dense cosine thresholds 0.2/0.3/0.4; lexical-only; lexical+dense reciprocal-rank fusion. Cosine thresholds apply before fusion and are never compared with RRF scores. Keep top-3 context and output budgets equal; report actual context-token cost. Generated-answer evaluation is separate from retrieval containment. Absent-source questions are a stress test, not guaranteed unanswerable truth.
- App overhead: compare original full-sort cosine with current normalized bounded top-K on identical deterministic vectors; check ranking agreement before latency. No database migration is in this decision.

Selection rule: retain the existing conservative phone settings unless device evidence supports a change. For retrieval, require no held-out EN/ES answer-containment regression and no new app mechanism unless generated-answer quality justifies it; ties favor fewer chunks and less code. Larger models, a new embedding model/database, speculative decoding, and approximate search are outside this patch: no measured failure currently justifies their complexity.

Empty decision matrix recorded before measurement (historical; see the completed results above):

| Arm | Compatibility / quality | Timing distribution | Peak allocation | Decision scope |
|---|---|---|---|---|
| Custom Gemma / upstream | pending | pending | pending | Mac model/processor only |
| Cache 0 / 32 / 64 MiB, text/photo | pending | pending | pending | Mac only |
| MiniLM batch 1 / 4 / 8 | pending | pending | pending | Mac math/throughput only |
| Word baseline / token chunk grid | pending | pending | pending | MLQA EN/ES screening |
| Dense / lexical / fusion | pending | pending | pending | MLQA EN/ES screening |
| Full sort / bounded top-K | pending | pending | pending | CPU search correctness/cost |

An independent read-only review approved this scoped Mac plan with controls for the incumbent's hard capacity, app-level session coverage, article-disjoint retrieval splits, multiple image shapes, timing warm-up/synchronization, and reproducible raw artifacts. Those controls are incorporated above. **Actual Hermit `LLMService` behavior, memory warnings, iPhone inference/thermals, and full photo-answer regression remain separate device gates when the native harness cannot execute them.**

## Compatibility correction during execution

The first real load with release **3.31.4** failed with `MLXNN.UpdateError.keyNotFound` at `language_model.model.layers.15.self_attn.k_norm.weight`. This is the known [upstream shared-KV loader defect](https://github.com/ml-explore/mlx-swift-lm/issues/552). Compilation and simulator tests did not cover it.

The app now pins the **merged upstream fix**, `68947ccdca79bcf7a26dc220f73caa060369513c` ([PR #384](https://github.com/ml-explore/mlx-swift-lm/pull/384)); no local Gemma code was restored. Native loading with `mlx-community/gemma-4-e2b-it-4bit` revision `238767527555cb75a05732a84dff5d6ba0dd6809` succeeds and the deterministic prompt “Reply with only the capital of France.” returns `PARIS` on the Mac. The [two-cat photo](https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/coco_sample.png) with “How many cats are in this image? Reply with only the number.” returns `2` (335 prepared input tokens). These are compatibility smoke checks, not performance or quality comparisons. The wider comparison matrix remains pending; no tuning decision is based on these exploratory runs.

## Tokenizer correction before retrieval comparison

The first embedding run revealed that the deployed MiniLM `tokenizer.json` configures **fixed padding and truncation at 128 tokens**. Every reported length was 128, including long passages. The tokenizer adapter preserves these serialized settings. Thus the original word chunks can silently lose text, and the proposed token budget also fails unless those settings are cleared. All first-run token-grid results are superseded.

The app now passes a temporary tokenizer configuration without padding/truncation to the existing upstream loader, then applies its own explicit token budget and masked batch padding. Downloaded files stay unchanged. Since removing attended padding changes vectors, legacy records require reimporting and cannot participate in search.

The revised comparison retains the **actual deployed word-chunk baseline with its 128-token behavior**, adds an **untruncated word-chunk control** to isolate this defect, and reruns all token/overlap candidates with the corrected loader. The untruncated word control still rejects whole documents above the hard 512-position capacity. The corpus and article-disjoint query split are unchanged. Both encoded lengths and full lengths are recorded; generated-answer quality remains a separate check from answer-span retrieval.

Generated-answer screening uses the first 20 held-out questions per language in the seeded corpus order (40 shared questions, 160 answers). Compare deployed word/dense, corrected 256/32 dense, 256/32 fusion, and 256/0 lexical. Lexical 256/0 tied 256/32 on macro tuning recall (84.5%) with fewer chunks. These inputs use the actual app `LLMService`, its 4096/1024 budget and temperature 0.7, with MLX seed 20260919 per question, independent sessions, and the same request for a short answer in the question's language. Only retrieval changes between arms. This small screening set can motivate further evaluation; it cannot establish a production-quality winner. The native model-owner adapter does not test the iOS manager or memory warnings.

## Pooling correction before final results

The tokenizer-only run improved retrieval, but corrected cosine scores were suspiciously high even for unrelated passages. Inspection found that the MLX checkpoint omits `1_Pooling/config.json`; upstream falls back to BERT's classification pooler. The [MiniLM model card](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) and [pooling configuration](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/blob/main/1_Pooling/config.json) specify masked mean pooling followed by L2 normalization, without extra layer normalization.

The app now selects `MLXEmbedders.Pooling(strategy: .mean)` explicitly. The entire token grid, batch comparison, and the same generated-answer cases are rerun. Actual legacy and untruncated legacy controls retain classification pooling; a `tokenizer_only` 256/32 control isolates the additional pooling correction. Preceding tokenizer-only results are retained separately and do not describe the final app. The reimport requirement applies to both corrections.
