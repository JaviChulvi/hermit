#!/usr/bin/env python3
"""Prepare an isolated iOS validation project and inputs; never edit the app target."""
import json
import os
import shutil
import sys
import urllib.request
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
root, bundle, data = Path(sys.argv[1]).resolve(), sys.argv[2], Path(sys.argv[3]).resolve()
root.mkdir(parents=True, exist_ok=True)
spec = (repo / 'project.yml').read_text().replace('bundleIdPrefix: com.hermit', f'bundleIdPrefix: {bundle}')
for name in ['Hermit', 'HermitTests', 'Hermit/Resources']:
    spec = spec.replace(f'path: {name}\n', f'path: {repo / name}\n')
spec = spec.replace('CODE_SIGN_ENTITLEMENTS: Hermit/Hermit.entitlements',
                    f'CODE_SIGN_ENTITLEMENTS: {repo}/Hermit/Hermit.entitlements')
spec = spec.replace('PRODUCT_BUNDLE_IDENTIFIER: com.hermit.Hermit', f'PRODUCT_BUNDLE_IDENTIFIER: {bundle}')
spec = spec.replace(f'      - path: {repo}/HermitTests\n',
                    f'      - path: {repo}/HermitTests\n      - path: {repo}/benchmarks/DevicePerformanceTests.swift\n')
(root / 'project.yml').write_text(spec)
lock = Path('Hermit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
(root / lock).parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(repo / lock, root / lock)

corpus = json.loads((data / 'corpus.json').read_text())
results = repo / 'benchmarks/results/2026-09-19'
inputs = {
    'textPrompt': json.loads((results / 'cache-text.json').read_text())[0]['prompt'],
    'photoPrompt': json.loads((results / 'cache-photo.json').read_text())[0]['prompt'],
    'documents': [d['text'] for d in corpus['documents'][:32]],
    'queries': [q['text'] for language in ['en', 'es']
                for q in [q for q in corpus['questions'] if q['language'] == language][:16]],
}
(root / 'hermit-benchmark-inputs.json').write_text(json.dumps(inputs, ensure_ascii=False))

# HubClient verifies snapshots against its cached repository file list, not only
# refs/main. Stage that metadata as well as the exact downloaded model files.
for name, model, revision in [
    ('gemma', 'gemma-4-e2b-it-4bit', '238767527555cb75a05732a84dff5d6ba0dd6809'),
    ('minilm', 'all-MiniLM-L6-v2-bf16', 'b6691709eacd8f0afcc3faace288cf50e611f3aa'),
]:
    url = f'https://huggingface.co/api/models/mlx-community/{model}/revision/{revision}?blobs=true'
    with urllib.request.urlopen(url, timeout=30) as response:
        info = json.load(response)
    assert info['sha'] == revision
    siblings = [dict(path=f['rfilename'], type='file', size=f.get('size')) for f in info['siblings']]
    cache = root / 'model-cache'
    model_cache = cache / f'models--mlx-community--{model}'
    snapshot = model_cache / 'snapshots' / revision
    snapshot.mkdir(parents=True, exist_ok=True)
    for file in (data.parent / 'models' / name).iterdir():
        if not file.is_file() or file.name.startswith('.'):
            continue
        destination = snapshot / file.name
        if not destination.exists():
            try:
                os.link(file, destination)
            except OSError:
                shutil.copy2(file, destination)
    for entry in siblings:
        file = snapshot / entry['path']
        if file.is_file() and entry['size'] is not None:
            assert file.stat().st_size == entry['size'], file
    (model_cache / 'refs').mkdir(exist_ok=True)
    (model_cache / 'refs/main').write_text(revision)
    metadata = cache / '.metadata' / model_cache.name
    metadata.mkdir(parents=True, exist_ok=True)
    (metadata / f'{revision}.json').write_text(json.dumps(dict(commitHash=revision, siblings=siblings)))
print('Prepared device project and 32-passage/32-query inputs in', root)
