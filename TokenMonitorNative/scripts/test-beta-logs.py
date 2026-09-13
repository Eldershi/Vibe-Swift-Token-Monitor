#!/usr/bin/env python3
"""Real bundled parser, synthetic source tree; never substitutes the user's home."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
backend = args.app / 'Contents/Resources/Backend' if args.app else root / 'Backend'
binary = backend / 'node_modules/@tokscale/cli-darwin-arm64/bin/tokscale'

def claude(identifier, stamp, amount=100):
    return {'type': 'assistant', 'timestamp': stamp, 'sessionId': 'synthetic-claude',
            'requestId': 'synthetic-request-' + identifier,
            'message': {'id': 'synthetic-message-' + identifier, 'model': 'claude-sonnet-4-20250514',
                        'usage': {'input_tokens': amount, 'output_tokens': 50,
                                  'cache_read_input_tokens': 10, 'cache_creation_input_tokens': 20}}}

with tempfile.TemporaryDirectory(prefix='native-beta-log-tests-') as temp:
    directory = Path(temp); sources = directory / 'sources'; cache = directory / 'cache'
    claude_file = sources / '.claude/projects/synthetic/session.jsonl'
    codex_file = sources / '.codex/sessions/2026/09/01/rollout-synthetic.jsonl'
    claude_file.parent.mkdir(parents=True); codex_file.parent.mkdir(parents=True); cache.mkdir()
    first = claude('1', '2026-08-31T12:00:00Z')
    claude_file.write_text(json.dumps(first) + '\n')
    usage = {'input_tokens': 200, 'cached_input_tokens': 50, 'output_tokens': 80,
             'reasoning_output_tokens': 20, 'total_tokens': 280}
    codex = [{'type': 'session_meta', 'timestamp': '2026-09-01T12:00:00Z',
              'payload': {'id': 'synthetic-codex', 'timestamp': '2026-09-01T12:00:00Z', 'cwd': '/synthetic/project'}},
             {'type': 'turn_context', 'timestamp': '2026-09-01T12:00:01Z', 'payload': {'model': 'gpt-5'}},
             {'type': 'event_msg', 'timestamp': '2026-09-01T12:00:02Z',
              'payload': {'type': 'token_count', 'info': {'total_token_usage': usage, 'last_token_usage': usage}}}]
    codex_file.write_text('\n'.join(map(json.dumps, codex)) + '\n')
    pricing = {'models': {model: {'input_cost_per_million_tokens': 2, 'output_cost_per_million_tokens': 4,
                                 'cache_read_input_token_cost_per_million_tokens': 1,
                                 'cache_creation_input_token_cost_per_million_tokens': 3}
                          for model in ['gpt-5', 'claude-sonnet-4', 'claude-sonnet-4-20250514']}}
    (cache / 'custom-pricing.json').write_text(json.dumps(pricing))
    env = dict(os.environ, TOKSCALE_CONFIG_DIR=str(cache), PATH='/usr/bin:/bin', TZ='UTC')

    def scan(*flags, graph=False):
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources.rglob('*') if p.is_file()}
        command = [str(binary)] + (['graph'] if graph else ['--json', '--group-by', 'client,session,model'])
        result = subprocess.run(command + ['--home', str(sources), '--client', 'codex,claude', '--no-spinner', *flags],
                                env=env, capture_output=True, text=True, check=True, timeout=45)
        after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources.rglob('*') if p.is_file()}
        assert before == after, 'scanner modified source logs'
        return json.loads(result.stdout)

    initial = scan('--since', '2026-01-01')
    assert initial['totalMessages'] == 2
    by_client = {row['client']: row for row in initial['entries']}
    assert [by_client['codex'][key] for key in ['input', 'output', 'cacheRead', 'reasoning']] == [150, 60, 50, 20]
    assert abs(initial['totalCost'] - 0.00114) < 1e-10
    repeated = scan('--since', '2026-01-01')
    assert repeated['entries'] == initial['entries'], 'restart double-counted source data'
    month = scan('--since', '2026-09-01')
    assert [row['client'] for row in month['entries']] == ['codex']
    graph = scan('--since', '2026-01-01', graph=True)
    assert [(row['date'], row['totals']['tokens']) for row in graph['contributions']] == [('2026-08-31', 180), ('2026-09-01', 280)]
    with claude_file.open('a') as output:
        output.write(json.dumps(claude('2', '2026-09-02T12:00:00Z')) + '\n')
    assert scan('--since', '2026-01-01')['totalMessages'] == 3
    # The pinned parser retains already observed messages in its durable cache.
    # Truncation must neither add them again nor erase recorded historical usage.
    claude_file.write_text(json.dumps(first) + '\n')
    truncated = scan('--since', '2026-01-01')
    assert truncated['totalMessages'] == 3, truncated
    archived = sources / '.codex/archived_sessions'
    archived.mkdir(); codex_file.rename(archived / codex_file.name)
    assert scan('--since', '2026-01-01')['totalMessages'] == 3
    claude_file.write_text(json.dumps(claude('zero', '2026-09-03T12:00:00Z', 0)).replace('"output_tokens": 50', '"output_tokens": 0').replace('"cache_read_input_tokens": 10', '"cache_read_input_tokens": 0').replace('"cache_creation_input_tokens": 20', '"cache_creation_input_tokens": 0') + '\n')
    assert scan('--since', '2026-01-01')['totalMessages'] >= 1
    print('PASS: bundled parser, token partitions, deterministic cost, restart, month boundary, daily history, append, truncate, rotation, zero usage and read-only sources')
