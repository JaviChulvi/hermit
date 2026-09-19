# Native validation results — 2026-09-19

**The upstream package loads Gemma successfully; phone validation and retrieval acceptance remain open.** Retain cache=0 / batch=1 while validating. The corrected original-stack comparison gives English Recall@3 64% → 78% and Spanish 45% → 43%. The Spanish result fails the preregistered no-regression gate; the current retrieval settings are provisional, not an accepted multilingual improvement.

**Baseline correction:** the earlier report mislabeled `legacy` as the original app. That arm runs old app logic on the new tokenizer, which honors serialized 128-token padding/truncation. The original locked tokenizer 0.2.1 ignores those settings. Its separately executed `original_stack` arm is now the before/after baseline below. The earlier 10%/7% scores remain as a migration-regression control, not original-app quality.

App revision: `e2b721e`. M3 Pro / 36 GiB, macOS 26.6.1, Xcode 26.4. [Raw evidence](results/2026-09-19/), [reproduction](REPRODUCE.md), and the [preregistered plan and corrections](README.md) accompany this report. This was a local interactive host, with sequential GPU workloads, not a dedicated iPhone test rig. No paid inference API or user documents were used.

A subsequent cache-path fix resolves relative Hugging Face symlinks before copying tokenizer metadata. Its regression test passes with the same 50-pass/5-skip suite. The measurements above used regular files and are retained at their original source revision; the path fix does not change tokenization or pooling for those inputs.

## Compatibility and session behavior

| Check | Observed result | Scope |
|---|---|---|
| Original custom Gemma on original locked stack/checkpoint | Load fails: missing layer 15 shared-KV `k_proj.weight` | No original output exists for comparison |
| Custom Gemma on current runtime/checkpoint | Load fails: packed projection shape `[8960,192]` vs expected `[8960,1536]` | Separate runtime-migration control |
| Tagged upstream 3.31.4 | Load fails on missing shared-KV `k_norm.weight` | Superseded by upstream fix |
| Pinned upstream `68947cc` | Text, real photo, and three aspect-ratio fixtures generate successfully | Native compatibility only |
| Shape/color/OCR fixtures | All three answer “Red circle, blue square, green triangle. MAP 42” | Simple generated fixtures, not real-photo quality coverage |
| Actual `LLMService` | Seven structural checks pass; cached follow-up returns `cobalt7`, changed document context returns `amber9`; photo and follow-up both return `2` | Native model-owner adapter; iOS manager is not exercised |
| App tests/build | 50 passed, 5 explicitly skipped; generic iOS unsigned build passes | Physical MLX integration tests remain skipped |

The service checks verify retained session identity, prefix reset, history trimming, rejection of oversized current input, unload-callback reset, photo-history reuse, and combined image/text budget rejection. The photo turn accounts for 347 tokens and its follow-up reaches 371. The original-stack control uses unchanged `dd98f8e` model source and all 16 original lockfile pins (MLX 0.31.3, fork `d18efe1`, tokenizer 0.2.1). It also fails with the current checkpoint. No older working checkpoint or installed binary was compared. The current-runtime control uses a protocol forwarding adapter and remains separately identified.

## Retrieval quality

MLQA development data supplies 978 English and 454 Spanish passages. The fixed split uses source articles, with 100 tuning and 100 held-out questions per language. Search runs separately by language. A hit requires the correct source passage and containment of the annotated answer span in a returned chunk; matching the answer string in another source does not count. All rows below use dense cosine threshold 0.2 and top-3. Confidence intervals are Wilson 95% intervals for each 100-question proportion, not paired significance tests.

| Pipeline | Chunks | Failed documents | English answer Recall@3 [CI] | Spanish answer Recall@3 [CI] | Change vs original EN / ES | Mean context MiniLM tokens EN / ES |
|---|---:|---:|---:|---:|---:|---:|
| **Original locked stack: words + classification pooler** | 1679 | 12 | 64% [54, 73] | 45% [36, 55] | +0 / +0 pp | 621 / 643 |
| Legacy logic on new stack (`legacy`): serialized tokenizer | 1712 | 0 | 10% [6, 17] | 7% [3, 14] | -54 / -38 pp | 75 / 96 |
| New stack: untruncated words + classification pooler | 1679 | 12 | 64% [54, 73] | 45% [36, 55] | +0 / +0 pp | 621 / 645 |
| 256/32 tokens + classification pooler | 1909 | 0 | 61% [51, 70] | 48% [38, 58] | -3 / +3 pp | 527 / 551 |
| Mean pooling: 128 / 0 | 2987 | 0 | 73% [64, 81] | 39% [30, 49] | +9 / -6 pp | 247 / 211 |
| Mean pooling: 128 / 32 | 3319 | 0 | 77% [68, 84] | 43% [34, 53] | +13 / -2 pp | 283 / 263 |
| Mean pooling: 192 / 0 | 2255 | 0 | 75% [66, 82] | 41% [32, 51] | +11 / -4 pp | 328 / 291 |
| Mean pooling: 192 / 32 | 2322 | 0 | 78% [69, 85] | 45% [36, 55] | +14 / +0 pp | 373 / 354 |
| Mean pooling: 256 / 0 | 1879 | 0 | 77% [68, 84] | 43% [34, 53] | +13 / -2 pp | 390 / 315 |
| **App: mean pooling 256 / 32 (provisional)** | 1909 | 0 | 78% [69, 85] | 43% [34, 53] | +14 / -2 pp | 401 / 385 |

The `legacy` migration control silently truncated 977 of 1,712 chunks to 128 tokens. This is new-tokenizer behavior, not original-stack behavior. Both untruncated word controls encounter 12 Spanish documents exceeding the hard 512-position limit. The harness rejects those whole documents to avoid undefined gathers; the original app has no such guard. Every token-based candidate indexes all 1,432 documents. On the common-eligible Spanish held-out subset (93 questions), the original stack scores 48.4% and the app 44.1%; failures do not explain away the regression. Full and common-eligible scores are in the JSON summary.

Masked mean pooling is the documented MiniLM contract; the checkpoint omits the metadata that would select it automatically. Its English score improves over the tokenizer-only classification-pooler control, while its Spanish score is 5 points lower on this sample. The app also scores 2 points below the original stack in Spanish. Do not select another chunk size using the now-visible held-out scores or claim the no-regression gate passed. A separately registered evaluation is needed before accepting a retrieval winner.

| Search on corrected 256/32 chunks | English Recall@3 | Spanish Recall@3 | Change vs dense 0.2 EN / ES | Mean context MiniLM tokens EN / ES |
|---|---:|---:|---:|---:|
| **dense_0.2 (app default)** | 78% | 43% | +0 / +0 pp | 401 / 385 |
| dense_0.3 | 75% | 43% | -3 / +0 pp | 377 / 385 |
| dense_0.4 | 68% | 43% | -10 / +0 pp | 222 / 385 |
| lexical | 77% | 80% | -1 / +37 pp | 483 / 500 |
| fusion_0.2 | 88% | 61% | +10 / +18 pp | 456 / 513 |
| fusion_0.3 | 85% | 61% | +7 / +18 pp | 446 / 513 |
| fusion_0.4 | 81% | 61% | +3 / +18 pp | 472 / 514 |

Lexical search uses in-memory SQLite FTS5 BM25 (`unicode61`, diacritics removed), OR query terms, and 50 candidates. Fusion sums `1/(60+rank)` across the top 50 lexical and dense results; thresholds gate only the dense list before fusion. Lexical hits can enter independently. SQLite is used only by the benchmark. There is no new app database or lexical retrieval implementation.

## Generated answers

The same 20 held-out questions per language produce 160 answers across four retrieval arms through the actual app generation service. All four use the new package stack and generator; `legacy` is the migration-regression control, not the original app or original-stack retrieval. Thus this pilot provides no before/after answer-quality estimate. Sessions reset between cases; seed=20260919, temperature=0.7, app context/output budgets=4096/1024. The maximum observed session length is 935 tokens. Exact match and token F1 use lexical normalization, not human correctness grading; Spanish phrases can be semantically correct while failing exact match. These are small pilot samples, not production acceptance rates.

| Retrieval arm (new stack) | EN exact match | EN token F1 | ES exact match | ES token F1 | F1 change vs migration control EN / ES | Questions / language |
|---|---:|---:|---:|---:|---:|---:|
| legacy/dense_0.2 | 5% | 8.3% | 0% | 4.2% | +0.0 / +0.0 pp | 20 |
| **256_32/dense_0.2 (app)** | 45% | 69.3% | 0% | 14.8% | +60.9 / +10.6 pp | 20 |
| 256_32/fusion_0.2 | 45% | 74.3% | 0% | 19.4% | +66.0 / +15.3 pp | 20 |
| 256_0/lexical | 45% | 69.3% | 5% | 33.3% | +60.9 / +29.1 pp | 20 |

Lexical and fusion merit a larger evaluation on actual document questions, particularly Spanish. This corpus contains short, sometimes underspecified standalone questions with substantial lexical overlap. The pilot is insufficient to add another retrieval mechanism to the app or claim calibrated abstention. No verified unanswerable-question set was available.

## Memory and latency

All timing tables exclude one warm-up per setting and report five interleaved repeats. Ranges and IQRs describe these runs; five repeats cannot establish a stable p95. MLX peak allocation excludes total process RSS and iOS jetsam limits. Cache runs clear allocator cache before each request, keep model weights loaded, and use fresh sessions. Outputs and token counts are identical across cache settings within each workload.

| Workload / cache MiB | Response median (s) | IQR (s) | Range (s) | Change vs cache 0 | Prefill / decode median (s) | Peak MLX MiB |
|---|---:|---:|---:|---:|---:|---:|
| **text / 0** | 1.199 | 0.068 | 1.145–1.231 | +0.0% | 0.155 / 1.031 | 3213.3 |
| text / 32 | 1.163 | 0.011 | 1.153–1.181 | -2.9% | 0.156 / 1.000 | 3213.3 |
| text / 64 | 1.179 | 0.018 | 1.157–1.193 | -1.7% | 0.156 / 1.010 | 3213.3 |
| **photo / 0** | 1.819 | 0.008 | 1.816–1.829 | +0.0% | 0.842 / 0.963 | 3763.4 |
| photo / 32 | 1.818 | 0.038 | 1.811–1.920 | -0.0% | 0.842 / 0.964 | 3763.4 |
| photo / 64 | 1.811 | 0.002 | 1.807–1.824 | -0.4% | 0.840 / 0.959 | 3763.4 |

The text workload generates 76 tokens; the photo workload generates 74. Photo prefill is measured separately, not inferred from text timings. Small cache changes are within a few percent on this host and do not justify raising the phone limit.

| Embedding batch (43 chunks) | Median (ms) | IQR (ms) | Range (ms) | Change vs batch 1 | Peak MLX MiB | Minimum cosine vs singles | Exact top-3 order agreement (32 queries) |
|---|---:|---:|---:|---:|---:|---:|---:|
| **1 (app default)** | 145.8 | 1.3 | 145.0–146.8 | +0.0% | 88.0 | 1.000000 | 100.00% |
| 4 | 122.2 | 3.6 | 121.2–127.1 | -16.1% | 149.9 | 0.999936 | 90.62% |
| 8 | 115.5 | 0.6 | 115.0–117.1 | -20.8% | 220.4 | 0.999947 | 93.75% |

The batch sample uses the first 32 interleaved-language passages (43 chunks), with 16 English and 16 Spanish ranking probes. Small batches trade speed for higher peak allocation and small floating-point changes that sometimes reorder near ties. Batch 1 remains the app default.

## Search overhead

| 384-dimensional vectors | Full sort + repeated norms median (ms/query) | Normalized bounded top-3 median (ms/query) | Bounded range (ms/query) | Change | Rank agreement |
|---|---:|---:|---:|---:|---:|
| 1,000 | 0.161 | 0.054 | 0.051–0.065 | -66.5% | 100% |
| 10,000 | 1.137 | 0.467 | 0.420–0.496 | -58.9% | 100% |
| 30,000 | 3.852 | **1.564** | 1.508–1.605 | -59.4% | 100% |

Ten seeded queries per repeat use independently generated vectors, not duplicate tiling. This isolates CPU search cost and verifies top-3 ordering against the original full-sort cosine calculation. It is not a semantic-quality test or a full UI responsiveness measurement.

## Remaining gates

- Physical iPhone inference, memory warnings, cancellation under GPU load, sustained thermals, and measured UI responsiveness remain unverified. Device results will be recorded with the actual connected hardware.
- Original-vs-upstream photo/answer regression remains unresolved because the unchanged custom model fails on both the original locked stack and current runtime with the current checkpoint. Existing simple upstream fixtures do not replace that comparison.
- The Spanish retrieval no-regression gate fails against the corrected original-stack baseline. Current retrieval parameters remain provisional; this report does not approve merging them as a quality improvement.
- Spanish answer quality and abstention need broader, human-checked document queries. Lexical/fusion are measured candidates, not shipped features or established production winners.
- Local artifacts remain under `/tmp/hermit-bench`; there is no cloud resource or paid service to tear down. Models, raw vectors, and the corpus stay outside the app repository. The reproducible summaries and outputs are committed; no user data was modified.
- The PR remains draft. These findings justify the tokenizer/pooling corrections and continued validation, not completion of the physical-device gates.
