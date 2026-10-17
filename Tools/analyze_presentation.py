#!/usr/bin/env python3
"""Audit drawable callbacks and refresh timing without equating callbacks to scanout.

Usage: analyze_presentation.py work/perf/TEST [--output PATH]
Selects the latest Viewer session and the test's settled +5/-2 second interval.
When Host trace is present, uses its packed sequence selection, matching
analyze_stalls.py. No images, addresses, or credentials are read or emitted.
"""
import argparse
import bisect
import collections
import gzip
import json
import math
from pathlib import Path
import statistics


def load(directory, name):
    path = directory / name
    if path.exists():
        content = path.read_text()
    elif Path(str(path) + '.gz').exists():
        with gzip.open(str(path) + '.gz', 'rt') as stream:
            content = stream.read()
    else:
        return []
    events = []
    for line in content.splitlines():
        try:
            events.extend(json.loads(line))
        except json.JSONDecodeError:
            pass
    return sorted(events, key=lambda event: event['t'])


def summary(values):
    if not values:
        return None
    values = sorted(values)
    return {
        'count': len(values), 'mean': statistics.mean(values),
        'p50': values[len(values) // 2],
        'p95': values[min(len(values) - 1, int(len(values) * .95))],
        'p99': values[min(len(values) - 1, int(len(values) * .99))],
        'min': values[0], 'max': values[-1],
    }


def refresh_fit(times):
    """Fit timestamps to integer refresh indices; excludes repeated timestamps."""
    times = sorted(set(times))
    if len(times) < 3:
        return None
    gaps = [b - a for a, b in zip(times, times[1:]) if b > a]
    nominal = statistics.median(gaps)
    indices = [0]
    for a, b in zip(times, times[1:]):
        indices.append(indices[-1] + max(1, round((b - a) / nominal)))
    mx, my = statistics.mean(indices), statistics.mean(times)
    slope = sum((x - mx) * (y - my) for x, y in zip(indices, times)) / sum((x - mx) ** 2 for x in indices)
    intercept = my - slope * mx
    return {
        'period_ms': slope * 1000, 'hz': 1 / slope,
        'max_fit_residual_ms': max(abs(y - (intercept + slope * x)) * 1000 for x, y in zip(indices, times)),
    }


def nearest(value, sorted_values):
    index = bisect.bisect_left(sorted_values, value)
    candidates = sorted_values[max(0, index - 1):min(len(sorted_values), index + 1)]
    return min(candidates, key=lambda candidate: abs(candidate - value))


def analyze(directory):
    meta = json.loads((directory / 'test.json').read_text())
    start, end = meta['began'] + 5, meta['finished'] - 2
    duration = end - start
    if duration <= 0:
        raise ValueError('The settled test interval must be longer than zero seconds')
    host = load(directory, 'host.trace.jsonl')
    viewer = load(directory, 'viewer.trace.jsonl')
    sessions = [event for event in viewer if event['event'] == 'viewer_session']
    if not sessions:
        raise ValueError('No Viewer session in trace')
    session = sessions[-1]
    viewer = [event for event in viewer if event.get('view') == session['view'] or event.get('link') == session['link']]
    rows = {}
    for event in viewer:
        if 'seq' in event:
            rows.setdefault(event['seq'], {})[event['event']] = event
    if host:
        selected = sorted({event['seq'] for event in host if event['event'] == 'packed' and start <= event['wall'] <= end})
        selection = 'Host packed sequence in test +5/-2 second interval'
    else:
        selected = sorted(sequence for sequence, row in rows.items() if 'gpu_commit' in row and start <= row['gpu_commit']['wall'] <= end)
        selection = 'Viewer gpu_commit in test +5/-2 second interval'
    matched = [sequence for sequence in selected if 'presented' in rows.get(sequence, {})]
    positive = [sequence for sequence in matched if rows[sequence]['presented'].get('presented_time', 0) > 0]
    zero = [sequence for sequence in matched if rows[sequence]['presented'].get('presented_time', 0) == 0]
    by_time = collections.defaultdict(list)
    for sequence in positive:
        by_time[rows[sequence]['presented']['presented_time']].append(sequence)
    positive_times = sorted(by_time)
    duplicates = [{'presented_time': time, 'sequences': sequences} for time, sequences in sorted(by_time.items()) if len(sequences) > 1]
    zero_detail = []
    for sequence in zero:
        row = rows[sequence]
        item = {'sequence': sequence, 'callback_time': row['presented']['t']}
        previous_positive = next((n for n in range(sequence - 1, max(0, sequence - 8), -1) if rows.get(n, {}).get('presented', {}).get('presented_time', 0) > 0), None)
        next_positive = next((n for n in range(sequence + 1, sequence + 8) if rows.get(n, {}).get('presented', {}).get('presented_time', 0) > 0), None)
        gpu_end = row.get('gpu_callback', {}).get('gpu_end')
        if next_positive is not None:
            next_row = rows[next_positive]
            next_time = next_row['presented']['presented_time']
            item.update(next_positive_sequence=next_positive, next_positive_time=next_time,
                        callback_minus_next_positive_time_ms=(row['presented']['t'] - next_time) * 1000,
                        next_callback_delta_ms=(next_row['presented']['t'] - row['presented']['t']) * 1000)
            if gpu_end is not None:
                item['gpu_ready_before_next_positive_ms'] = (next_time - gpu_end) * 1000
        if previous_positive is not None and gpu_end is not None:
            item['gpu_ready_before_previous_positive_ms'] = (rows[previous_positive]['presented']['presented_time'] - gpu_end) * 1000
        zero_detail.append(item)
    groups = []
    for item in zero_detail:
        if not groups or item['callback_time'] - groups[-1][-1]['callback_time'] > 1:
            groups.append([])
        groups[-1].append(item)
    zero_times = [item['callback_time'] for item in zero_detail]
    concentration = {}
    if zero_times:
        for period in [1, 4, 5, 8]:
            concentration[str(period)] = math.hypot(sum(math.cos(t * 2 * math.pi / period) for t in zero_times), sum(math.sin(t * 2 * math.pi / period) for t in zero_times)) / len(zero_times)
    anomalies = [{'sequence': sequence, 'presented_minus_gpu_end_ms': (rows[sequence]['presented']['presented_time'] - rows[sequence]['gpu_callback']['gpu_end']) * 1000} for sequence in positive if 'gpu_callback' in rows[sequence] and rows[sequence]['presented']['presented_time'] < rows[sequence]['gpu_callback'].get('gpu_end', 0)]
    refresh = [event for event in viewer if event['event'] == 'display_refresh' and start <= event['wall'] <= end]
    outputs = sorted(set(event['output_host'] for event in refresh if event.get('output_host_valid') and event.get('output_host', -1) > 0))
    refresh_info = {
        'callbacks': len(refresh), 'unique_output_predictions': len(outputs),
        'prediction_fit': refresh_fit(outputs),
        'reported_period_ms': summary([event['period'] * 1000 for event in refresh if event.get('period', -1) > 0]),
        'callback_gap_ms': summary([(b['t'] - a['t']) * 1000 for a, b in zip(refresh, refresh[1:])]),
    }
    if outputs:
        refresh_info['positive_timestamp_minus_nearest_output_prediction_ms'] = summary([(time - nearest(time, outputs)) * 1000 for time in positive_times if outputs[0] <= time <= outputs[-1]])
        refresh_info['zero_callback_minus_nearest_output_prediction_ms'] = summary([(time - nearest(time, outputs)) * 1000 for time in zero_times if outputs[0] <= time <= outputs[-1]])
    return {
        'seconds': duration, 'selection': selection, 'selected_frames': len(selected),
        'missing_presented_callbacks': len(selected) - len(matched),
        'positive_callbacks': len(positive), 'zero_timestamp_callbacks': len(zero),
        'unique_positive_timestamps': len(positive_times), 'duplicate_positive_timestamp_groups': len(duplicates),
        'repeated_positive_timestamp_callbacks': len(positive) - len(positive_times),
        'positive_callback_fps': len(positive) / duration,
        'unique_positive_timestamp_fps': len(positive_times) / duration,
        'unique_presentation_gap_ms': summary([(b - a) * 1000 for a, b in zip(positive_times, positive_times[1:])]),
        'presentation_timestamp_fit': refresh_fit(positive_times),
        'zero_frame_timing': {key: summary([item[key] for item in zero_detail if key in item]) for key in ['gpu_ready_before_next_positive_ms', 'gpu_ready_before_previous_positive_ms', 'callback_minus_next_positive_time_ms', 'next_callback_delta_ms']},
        'zero_time_concentration_by_period_seconds': concentration,
        'zero_groups': [{'first_sequence': group[0]['sequence'], 'last_sequence': group[-1]['sequence'], 'count': len(group), 'duration': group[-1]['callback_time'] - group[0]['callback_time']} for group in groups],
        'timestamp_order_anomalies': anomalies, 'duplicate_groups': duplicates, 'zero_frames': zero_detail,
        'display_clock': refresh_info,
        'surface_updates': [event for event in viewer if event['event'] == 'surface_update'],
        'limitations': [
            'A positive presentedTime callback is an API timestamp, not camera-verified physical scanout.',
            'Repeated positive timestamps share a refresh slot and must not be counted as distinct visible updates.',
            'Some GPU/driver timestamps may place presentation before gpuEndTime; inspect timestamp_order_anomalies before inferring deadlines.',
            'CVDisplayLink output_host is a refresh prediction, not a physical scanout measurement.',
            'All comparisons are within the Viewer clock; no Host/Viewer monotonic timestamps are subtracted.',
        ],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = analyze(args.directory)
    output = args.output or args.directory / 'presentation-analysis.json'
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"{args.directory.name}: {report['positive_callback_fps']:.2f} positive callbacks/s, "
          f"{report['unique_positive_timestamp_fps']:.2f} unique timestamps/s; "
          f"zero {report['zero_timestamp_callbacks']}, repeats {report['repeated_positive_timestamp_callbacks']}, "
          f"missing {report['missing_presented_callbacks']}; refresh callbacks {report['display_clock']['callbacks']}")
