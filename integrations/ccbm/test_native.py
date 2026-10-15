"""Requires actual compiled CCBM binaries; never substitutes a mock engine."""
from pathlib import Path
import json
import time
from server import infer

base = Path(__file__).parent / 'out'
sequences = [
    ['begin_check', 'check_responsiveness', 'call_emergency', 'check_breathing',
     'compression', 'ventilation', 'ventilation', 'ventilation', 'ventilation', 'handover'],
    ['begin_check', 'check_responsiveness', 'call_emergency', 'check_breathing',
     'compression_only', 'compression', 'handover'],
]
results = []
for sequence in sequences:
    for length in range(1, len(sequence) + 1):
        start = time.monotonic()
        result = infer(sequence[:length], base / 'p-filter', base / 'p.states')
        result['elapsed_ms'] = round((time.monotonic() - start) * 1000, 1)
        result['expected'] = sequence[length - 1]
        results.append(result)
        print(json.dumps(result), flush=True)
        assert result['action'] == result['expected'], result
        assert result['probability'] >= 0.90, result
print('NATIVE_CCBM_PASS', len(results), 'prefixes')
