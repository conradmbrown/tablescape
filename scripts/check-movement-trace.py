#!/usr/bin/env python3
"""Check real native player/camera frame traces on the Lumbridge bridge route."""
import bisect
import csv
import json
import statistics
import sys

with open(sys.argv[1], newline='') as stream:
    rows = list(csv.DictReader(stream))
results = {}
for leg, expected, sequence in [('walk', 1 / .6, '819'), ('run', 2 / .6, '824')]:
    # Exclude acceleration, stopping and the animation's idle transition.
    samples = [r for r in rows if r['leg'] == leg and 3225 < float(r['x']) < 3239]
    assert len(samples) > 60, f'{leg}: insufficient moving frames'
    assert {r['sequence'] for r in samples} == {sequence}, f'{leg}: unstable locomotion sequence'
    times = [float(r['time']) for r in samples]
    for column in ['x', 'cameraX']:
        speeds = []
        for i, row in enumerate(samples):
            # End-of-frame wall times include variable rendering work. Measure
            # over 150 ms (well below a server tick), rather than CPU frame noise.
            j = bisect.bisect_left(times, times[i] + .15)
            if j < len(samples):
                speeds.append(abs(float(samples[j][column]) - float(row[column])) / (times[j] - times[i]))
        mean = statistics.mean(speeds)
        cv = statistics.stdev(speeds) / mean
        results[f'{leg}_{column}'] = dict(speed=round(mean, 3), variation=round(cv, 3), minimum=round(min(speeds), 3))
        if '--report-only' not in sys.argv:
            assert abs(mean - expected) < expected * .15, (leg, column, mean)
            assert cv < .15, (leg, column, cv)
            assert min(speeds) > expected * .35, (leg, column, 'mid-route pause')
print(json.dumps(results, indent=2))
