# Hermit performance validation

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

Empty decision matrix (filled only after the relevant run):

| Arm | Compatibility / quality | Timing distribution | Peak allocation | Decision scope |
|---|---|---|---|---|
| Custom Gemma / upstream | pending | pending | pending | Mac model/processor only |
| Cache 0 / 32 / 64 MiB, text/photo | pending | pending | pending | Mac only |
| MiniLM batch 1 / 4 / 8 | pending | pending | pending | Mac math/throughput only |
| Word baseline / token chunk grid | pending | pending | pending | MLQA EN/ES screening |
| Dense / lexical / fusion | pending | pending | pending | MLQA EN/ES screening |
| Full sort / bounded top-K | pending | pending | pending | CPU search correctness/cost |

An independent read-only review approved this scoped Mac plan with controls for the incumbent's hard capacity, app-level session coverage, article-disjoint retrieval splits, multiple image shapes, timing warm-up/synchronization, and reproducible raw artifacts. Those controls are incorporated above. **Actual Hermit `LLMService` behavior, memory warnings, iPhone inference/thermals, and full photo-answer regression remain separate device gates when the native harness cannot execute them.**
