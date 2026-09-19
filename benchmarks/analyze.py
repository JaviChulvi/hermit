#!/usr/bin/env python3
"""Score saved MLQA retrieval runs; requires numpy==2.4.3, no model/API calls."""
import collections
import gzip
import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

import numpy as np

root = Path(sys.argv[1])
corpus = json.loads((root / 'corpus.json').read_text())
truth = json.loads((root / 'truth.json').read_text())
documents = {d['id']: d for d in corpus['documents']}
arms = ['legacy', 'legacy_full', 'tokenizer_only', '128_0', '128_32', '192_0', '192_32', '256_0', '256_32']
summaries, per_query, lengths = [], [], []


def norm(text):
    return ' '.join(text.split())


def covers(chunk, answer):
    if chunk['document'] != answer['document']:
        return False
    original = documents[chunk['document']]['text']
    for annotation in answer['answers']:
        start = annotation['answer_start']
        end = start + len(annotation['text'])
        assert original[start:end] == annotation['text']
        # A sentinel preserves the separator before an answer at a word boundary.
        left = len(norm(original[:start] + '\u00a4')) - 1
        right = len(norm(original[:end]))
        if chunk['start'] <= left and right <= chunk['end']:
            return True
    return False


for arm in arms:
    data = json.loads((root / f'corrected-{arm}.json').read_text())
    previous = collections.defaultdict(lambda: -1)
    for chunk in data['chunks']:
        document = chunk['document']
        start = norm(documents[document]['text']).find(norm(chunk['text']), previous[document] + 1)
        assert start >= 0, (arm, document, chunk['index'])
        chunk['start'], chunk['end'] = start, start + len(norm(chunk['text']))
        previous[document] = start
    for language in ['en', 'es']:
        chunks = [c for c in data['chunks'] if c['language'] == language]
        queries = [q for q in data['queries'] if q['language'] == language]
        embeddings = np.asarray([c['vector'] for c in chunks], dtype=np.float32)
        embeddings /= np.linalg.norm(embeddings, axis=1, keepdims=True)
        qvectors = np.asarray([q['vector'] for q in queries], dtype=np.float32)
        qvectors /= np.linalg.norm(qvectors, axis=1, keepdims=True)
        scores = qvectors @ embeddings.T
        failed = {x['document'] for x in data['failures']}
        lengths.append(dict(arm=arm, language=language, chunks=len(chunks),
            failedDocuments=sum(documents[d]['language'] == language for d in failed),
            queriesWithFailedSource=sum(q['document'] in failed for q in queries),
            fullTokenMedian=float(np.median([c['fullTokens'] for c in chunks])),
            fullTokenMax=max(c['fullTokens'] for c in chunks),
            truncatedChunks=sum(c['fullTokens'] > c['tokens'] for c in chunks)))
        connection = sqlite3.connect(':memory:')
        connection.execute("create virtual table passages using fts5(text, tokenize='unicode61 remove_diacritics 2')")
        connection.executemany('insert into passages(rowid,text) values(?,?)', enumerate(c['text'] for c in chunks))
        metrics = collections.defaultdict(list)
        for qi, query in enumerate(queries):
            answer = truth[query['id']]
            dense = np.argsort(-scores[qi], kind='stable').tolist()
            words = dict.fromkeys(re.findall(r'\w+', query['text'], re.UNICODE))
            expression = ' OR '.join('"' + w + '"' for w in words)
            lexical = [r[0] for r in connection.execute(
                'select rowid from passages where passages match ? order by bm25(passages),rowid limit 50', (expression,))] if expression else []
            rankings = {'lexical': lexical[:3]}
            for threshold in [.2, .3, .4]:
                selected = [i for i in dense if scores[qi, i] >= threshold]
                rankings[f'dense_{threshold}'] = selected[:3]
                fusion = collections.defaultdict(float)
                # Gate the dense list in cosine space; lexical has its own ranking.
                for ordered in [selected[:50], lexical]:
                    for rank, index in enumerate(ordered, 1):
                        fusion[index] += 1 / (60 + rank)
                rankings[f'fusion_{threshold}'] = sorted(fusion, key=lambda i: (-fusion[i], i))[:3]
            for method, indices in rankings.items():
                hits = [covers(chunks[i], answer) for i in indices]
                row = dict(arm=arm, method=method, language=language, split=answer['split'],
                    question=query['id'], hit=any(hits),
                    source=any(chunks[i]['document'] == query['document'] for i in indices),
                    mrr=next((1 / (rank + 1) for rank, hit in enumerate(hits) if hit), 0),
                    contextMiniLMTokens=sum(chunks[i]['fullTokens'] for i in indices),
                    returned=len(indices), sourceFailed=query['document'] in failed,
                    top=[dict(document=chunks[i]['document'], index=chunks[i]['index'],
                              cosine=float(scores[qi, i]), hit=hits[rank]) for rank, i in enumerate(indices)])
                metrics[(answer['split'], method)].append(row)
                per_query.append(row)
        for (split, method), rows in metrics.items():
            summaries.append(dict(arm=arm, language=language, split=split, method=method, queries=len(rows),
                answerRecall3=sum(r['hit'] for r in rows) / len(rows),
                sourceRecall3=sum(r['source'] for r in rows) / len(rows),
                mrr=float(np.mean([r['mrr'] for r in rows])),
                emptyResults=sum(not r['returned'] for r in rows),
                meanContextMiniLMTokens=float(np.mean([r['contextMiniLMTokens'] for r in rows])),
                failedSourceQueries=sum(r['sourceFailed'] for r in rows)))
        connection.close()
    print(arm, 'scored', flush=True)

# Wrong-source controls must fail even when the answer string occurs elsewhere.
sample = data['chunks'][0].copy()
sample['document'] = 'absent-source'
assert not covers(sample, next(iter(truth.values())))
failed_questions = {r['question'] for r in per_query if r['sourceFailed']}
for summary in summaries:
    eligible = [r for r in per_query if r['question'] not in failed_questions
                and all(r[k] == summary[k] for k in ['arm', 'language', 'split', 'method'])]
    summary['commonEligibleQueries'] = len(eligible)
    summary['commonEligibleAnswerRecall3'] = sum(r['hit'] for r in eligible) / len(eligible)
(root / 'retrieval-summary.json').write_text(json.dumps(dict(lengths=lengths, scores=summaries), indent=2))
with gzip.open(root / 'retrieval-queries.jsonl.gz', 'wt') as output:
    for row in per_query:
        output.write(json.dumps(row) + '\n')

# The generated-answer pilot uses a fixed held-out subset and matched app budgets.
questions = []
for language in ['en', 'es']:
    questions += [q for q in corpus['questions'] if q['language'] == language
                  and truth[q['id']]['split'] == 'eval'][:20]
ranks = {(r['arm'], r['method'], r['question']): r for r in per_query}
texts = {arm: {(c['document'], c['index']): c['text'] for c in
              json.loads((root / f'corrected-{arm}.json').read_text())['chunks']}
         for arm in ['legacy', '256_0', '256_32']}
cases = []
for q in questions:
    for arm, method in [('legacy', 'dense_0.2'), ('256_32', 'dense_0.2'),
                        ('256_32', 'fusion_0.2'), ('256_0', 'lexical')]:
        context = '\n---\n'.join(texts[arm][r['document'], r['index']]
                                for r in ranks[arm, method, q['id']]['top'])
        cases.append(dict(id=q['id'], arm=arm + '/' + method, language=q['language'],
                          question=q['text'], context=context or 'No relevant document excerpts were found.'))
(root / 'answer-cases.json').write_text(json.dumps(cases, ensure_ascii=False))


def answer_tokens(text, language):
    text = ''.join(c for c in text.lower() if not unicodedata.category(c).startswith('P'))
    articles = {'en': {'a', 'an', 'the'}, 'es': {'un', 'una', 'unos', 'unas', 'el', 'la', 'los', 'las'}}[language]
    return [word for word in text.split() if word not in articles]


if (root / 'answers.json').exists():
    grouped, scored = collections.defaultdict(list), []
    for row in json.loads((root / 'answers.json').read_text()):
        prediction = answer_tokens(row['output'], row['language'])
        exact, f1 = 0, 0
        for gold in truth[row['id']]['answers']:
            target = answer_tokens(gold['text'], row['language'])
            common = sum((collections.Counter(prediction) & collections.Counter(target)).values())
            exact = max(exact, int(prediction == target))
            f1 = max(f1, 2 * common / (len(prediction) + len(target)) if prediction or target else 1)
        row.update(exact=exact, f1=f1)
        grouped[row['arm'], row['language']].append(row)
        scored.append(row)
    result = [dict(arm=arm, language=language, questions=len(rows),
                   exactMatch=float(np.mean([r['exact'] for r in rows])),
                   tokenF1=float(np.mean([r['f1'] for r in rows])))
              for (arm, language), rows in grouped.items()]
    (root / 'answer-summary.json').write_text(json.dumps(dict(summary=result, rows=scored), indent=2))
