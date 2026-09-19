#!/usr/bin/env python3
"""Prepare an isolated native harness from this PR and the immutable old model source."""
import hashlib
import json
import random
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
root = Path(sys.argv[1]).resolve()
(root / 'Sources').mkdir(parents=True, exist_ok=True)
lock = Path('project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
(root / 'HermitBench.xcodeproj' / lock).parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(repo / 'Hermit.xcodeproj' / lock, root / 'HermitBench.xcodeproj' / lock)
for name in ['Gemma4Text.swift', 'Gemma4Vision.swift', 'Gemma4VLM.swift', 'ChunkingStrategy.swift']:
    source = subprocess.check_output(['git', 'show', f'dd98f8e:Hermit/Services/{name}'], cwd=repo, text=True)
    if name == 'ChunkingStrategy.swift':
        name = 'LegacyChunkingStrategy.swift'
        source = source.replace('struct ChunkingStrategy', 'struct LegacyChunkingStrategy')
    (root / 'Sources' / name).write_text(source)
for source in ['Hermit/Services/ChunkingStrategy.swift', 'Hermit/Utilities/CosineSimilarity.swift', 'Hermit/Services/LLMService.swift', 'Hermit/Models/ChatMessage.swift', 'benchmarks/Runner.swift', 'benchmarks/Fixtures.swift', 'benchmarks/LegacyBridge.swift', 'benchmarks/Sessions.swift']:
    target = root / 'Sources' / Path(source).name
    if target.is_symlink() or target.exists():
        target.unlink()
    target.symlink_to(repo / source)
# Compile the exact app embedding implementation, not a reimplementation.
source = (repo / 'Hermit/Services/EmbeddingService.swift').read_text()
start = source.index('    private static func embed(')
end = source.index('\n}\n', start)
(root / 'Sources/AppEmbedding.swift').write_text(source[:source.index('final class EmbeddingService')]
    + source[start:end].replace('private static func', 'func', 1) + source[end + 2:])
packages = (repo / 'project.yml').read_text().split('packages:\n', 1)[1].split('\ntargets:', 1)[0]
(root / 'project.yml').write_text('''name: HermitBench
options:
  deploymentTarget: {macOS: "14.0"}
settings:
  base: {SWIFT_VERSION: "6.0", CODE_SIGNING_ALLOWED: NO}
packages:
''' + packages + '''
targets:
  HermitBench:
    type: tool
    platform: macOS
    sources: [Sources]
    dependencies:
      - {package: mlx-swift, product: MLX}
      - {package: mlx-swift, product: MLXNN}
      - {package: mlx-swift, product: MLXRandom}
      - {package: mlx-swift-lm, product: MLXVLM}
      - {package: mlx-swift-lm, product: MLXLLM}
      - {package: mlx-swift-lm, product: MLXLMCommon}
      - {package: mlx-swift-lm, product: MLXEmbedders}
      - {package: swift-tokenizers-mlx, product: MLXLMTokenizers}
''')

# MLQA dev only. All passages are distractors; first 100 article-shuffled queries per
# split/language are evaluated. Article-disjoint tuning/evaluation, fixed seed.
archive = root / 'data/MLQA_V1.zip'
corpus = {'documents': [], 'questions': []}
truth = {}
by_language = {}
with zipfile.ZipFile(archive) as z:
    for language in ['en', 'es']:
        data = json.loads(z.read(f'MLQA_V1/dev/dev-context-{language}-question-{language}.json'))['data']
        titles = sorted({d['title'] for d in data})
        random.Random(20260919).shuffle(titles)
        partitions = {title: ('tune' if i % 2 == 0 else 'eval') for i, title in enumerate(titles)}
        documents, questions = {}, {'tune': [], 'eval': []}
        for article in data:
            for paragraph in article['paragraphs']:
                text = paragraph['context']
                doc = language + '-' + hashlib.sha256((article['title'] + '\n' + text).encode()).hexdigest()[:16]
                documents[doc] = {'id': doc, 'text': text, 'language': language}
                for qa in paragraph['qas']:
                    qid = language + '-' + qa['id']
                    questions[partitions[article['title']]].append({'id': qid, 'text': qa['question'], 'document': doc, 'language': language})
                    truth[qid] = {'answers': qa['answers'], 'article': article['title'], 'split': partitions[article['title']], 'document': doc}
        rng = random.Random(20260919)
        for split in questions:
            rng.shuffle(questions[split])
            corpus['questions'] += questions[split][:100]
        by_language[language] = list(documents.values())
# Interleave languages so batch microbenchmarks cover both.
for index in range(max(map(len, by_language.values()))):
    for language in ['en', 'es']:
        if index < len(by_language[language]):
            corpus['documents'].append(by_language[language][index])
(root / 'data/corpus.json').write_text(json.dumps(corpus, ensure_ascii=False))
(root / 'data/truth.json').write_text(json.dumps({q['id']: truth[q['id']] for q in corpus['questions']}, ensure_ascii=False))
(root / 'data/provenance.json').write_text(json.dumps({'seed': 20260919,
    'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'documents_by_language': {k: len(v) for k, v in by_language.items()},
    'query_ids': [q['id'] for q in corpus['questions']],
    'app_embedding_sha256': hashlib.sha256(source.encode()).hexdigest()}, indent=2))
print(len(corpus['documents']), 'passages;', len(corpus['questions']), 'queries')
