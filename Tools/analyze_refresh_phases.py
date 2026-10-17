#!/usr/bin/env python3
"""Compare refresh-plan phases using settled Viewer intervals and matched sequences.

All timing intervals use one machine's monotonic clock. Positive drawable
timestamps are API evidence, not camera-confirmed physical scanout.
"""
import argparse
import bisect
import collections
import json
from pathlib import Path

from analyze_presentation import load, summary, refresh_fit


def analyze(directory):
    meta = json.loads((directory / 'test.json').read_text())
    host = load(directory, 'host.trace.jsonl')
    viewer = load(directory, 'viewer.trace.jsonl')
    session = [event for event in viewer if event['event'] == 'viewer_session'][-1]
    viewer = [event for event in viewer if event.get('view') == session['view'] or event.get('link') == session['link']]
    rows, host_rows = {}, {}
    for target, events in [(rows, viewer), (host_rows, host)]:
        for event in events:
            if 'seq' in event:
                target.setdefault(event['seq'], {})[event['event']] = event
    modes = [event for event in viewer if event['event'] == 'refresh_mode']
    if not modes:
        raise ValueError('No refresh_mode events found')
    output_predictions = sorted(set(event['output_host'] for event in viewer if event['event'] == 'display_refresh' and event.get('output_host_valid') and event.get('output_host', -1) > 0))
    phases = []
    for index, mode in enumerate(modes):
        # Older traces contain only anchored; those were the timed atTime probe.
        # Submission deadlines are a distinct clock and must never be treated
        # as an intended presentation target.
        policy = mode.get('policy', 'timed' if mode['anchored'] else 'native')
        raw_end = modes[index + 1]['wall'] if index + 1 < len(modes) else meta['finished']
        start = max(meta['began'] + 5, mode['wall'] + 5)
        end = min(meta['finished'] - 2, raw_end - 2)
        duration = end - start
        if duration <= 0:
            continue
        sequences = sorted(sequence for sequence, row in rows.items() if 'gpu_commit' in row and start <= row['gpu_commit']['wall'] <= end)
        delivered = [sequence for sequence, row in rows.items() if 'body_end' in row and row['body_end'].get('type') == 2 and start <= row['body_end']['wall'] <= end]
        completed = [sequence for sequence in sequences if 'gpu_callback' in rows[sequence]]
        acked = [sequence for sequence in sequences if 'ack_apply' in host_rows.get(sequence, {})]
        positive = [sequence for sequence in sequences if rows[sequence].get('presented', {}).get('presented_time', 0) > 0]
        zero = [sequence for sequence in sequences if 'presented' in rows[sequence] and rows[sequence]['presented'].get('presented_time', 0) == 0]
        targets = [sequence for sequence in sequences if 'refresh_target' in rows[sequence]]
        commit_targets = [sequence for sequence in sequences if 'commit_target' in rows[sequence]]
        times = collections.defaultdict(list)
        for sequence in positive:
            times[rows[sequence]['presented']['presented_time']].append(sequence)
        metrics = collections.defaultdict(list)
        target_slots = collections.Counter()
        target_details = []
        commit_target_details = []
        for sequence in sequences:
            row = rows[sequence]
            commit = row['gpu_commit']
            callback = row.get('gpu_callback')
            presented = row.get('presented', {}).get('presented_time', 0)
            if callback:
                metrics['gpu_ms'].append((callback['gpu_end'] - callback['gpu_start']) * 1000)
                metrics['pre_gpu_queue_ms'].append((callback['gpu_start'] - commit['t']) * 1000)
                if 'body_end' in row:
                    metrics['receiver_body_end_to_gpu_callback_ms'].append((callback['t'] - row['body_end']['t']) * 1000)
            if presented > 0:
                metrics['commit_to_positive_timestamp_ms'].append((presented - commit['t']) * 1000)
                if callback:
                    metrics['gpu_end_to_positive_timestamp_ms'].append((presented - callback['gpu_end']) * 1000)
            if 'decoded' in row:
                decode = row['decoded']
                metrics['render_queue_ms'].append((decode['render_start'] - decode['arrival']) * 1000)
                metrics['decode_ms'].append((decode['t'] - decode['render_start']) * 1000)
            if 'commit_target' in row:
                deadline = row['commit_target']
                detail = {'sequence': sequence, 'deadline': deadline['target'],
                          'wait_ms': deadline['wait_ms'], 'wake_late_ms': deadline['wake_late_ms'],
                          'commit_minus_deadline_ms': (commit['t'] - deadline['target']) * 1000}
                metrics['commit_pacing_wait_ms'].append(detail['wait_ms'])
                metrics['commit_pacing_wake_late_ms'].append(detail['wake_late_ms'])
                metrics['commit_minus_pacing_deadline_ms'].append(detail['commit_minus_deadline_ms'])
                if callback:
                    metrics['pacing_deadline_to_gpu_end_ms'].append((callback['gpu_end'] - deadline['target']) * 1000)
                if presented > 0:
                    detail['deadline_to_positive_timestamp_ms'] = (presented - deadline['target']) * 1000
                    metrics['pacing_deadline_to_positive_timestamp_ms'].append(detail['deadline_to_positive_timestamp_ms'])
                commit_target_details.append(detail)
            if 'refresh_target' in row:
                target = row['refresh_target']
                detail = {'sequence': sequence, 'target': target['target'], 'period': target['period'], 'positive': presented > 0, 'zero': sequence in zero}
                metrics['target_lead_ms'].append(target['lead_ms'])
                metrics['commit_to_target_ms'].append((target['target'] - commit['t']) * 1000)
                if callback:
                    margin = (target['target'] - callback['gpu_end']) * 1000
                    metrics['gpu_ready_before_target_ms'].append(margin)
                    detail['gpu_ready_before_target_ms'] = margin
                if presented > 0:
                    lateness = (presented - target['target']) * 1000
                    metrics['positive_timestamp_minus_target_ms'].append(lateness)
                    # Scheduler currently requests presentation 2 ms before its
                    # predicted refresh. Subtract that intentional lead before
                    # rounding the actual timestamp to a whole refresh slot.
                    missed = round((presented - target['target'] - .002) / target['period'])
                    target_slots[str(missed)] += 1
                    detail.update(positive_timestamp=presented, positive_timestamp_minus_target_ms=lateness, predicted_slots_late=missed)
                    pos = bisect.bisect_left(output_predictions, presented)
                    nearest = output_predictions[max(0, pos - 1):min(len(output_predictions), pos + 1)]
                    if nearest:
                        metrics['positive_minus_nearest_output_prediction_ms'].append((presented - min(nearest, key=lambda value: abs(value - presented))) * 1000)
                target_details.append(detail)
            host_row = host_rows.get(sequence, {})
            if 'packed' in host_row and 'ack_apply' in host_row:
                metrics['host_ack_cycle_ms'].append((host_row['ack_apply']['t'] - host_row['packed']['t']) * 1000)
        target_times = [rows[sequence]['refresh_target']['target'] for sequence in targets]
        metrics['target_spacing_ms'] = [(b - a) * 1000 for a, b in zip(target_times, target_times[1:])]
        commit_target_times = [rows[sequence]['commit_target']['target'] for sequence in commit_targets]
        metrics['commit_pacing_deadline_spacing_ms'] = [(b - a) * 1000 for a, b in zip(commit_target_times, commit_target_times[1:])]
        unique = sorted(times)
        metrics['unique_positive_gap_ms'] = [(b - a) * 1000 for a, b in zip(unique, unique[1:])]
        capture = [event for event in host if event['event'] == 'capture' and event.get('status') == 0 and start <= event['wall'] <= end]
        phases.append({
            'phase': mode['phase'], 'anchored': mode['anchored'], 'policy': policy, 'seconds': duration,
            'window_begin_wall': start, 'window_end_wall': end,
            'delivered_frames': len(delivered), 'gpu_committed_frames': len(sequences),
            'gpu_completed_frames': len(completed), 'host_acknowledged_frames': len(acked),
            'capture_fps': len(capture) / duration, 'delivered_fps': len(delivered) / duration,
            'gpu_completed_fps': len(completed) / duration, 'host_acknowledged_fps': len(acked) / duration,
            'positive_callbacks': len(positive), 'positive_callback_fps': len(positive) / duration,
            'unique_positive_timestamps': len(unique), 'unique_positive_timestamp_fps': len(unique) / duration,
            'zero_timestamp_callbacks': len(zero), 'repeated_positive_timestamps': len(positive) - len(unique),
            'zero_timestamp_fraction': len(zero) / len(sequences) if sequences else None,
            'repeated_timestamp_fraction': (len(positive) - len(unique)) / len(sequences) if sequences else None,
            'unique_positive_timestamp_fraction': len(unique) / len(sequences) if sequences else None,
            'missing_presented_callbacks': len(sequences) - len(positive) - len(zero),
            'targeted_frames': len(targets), 'untargeted_frames': len(sequences) - len(targets),
            'commit_paced_frames': len(commit_targets),
            'commit_paced_fraction': len(commit_targets) / len(sequences) if sequences else None,
            'fallback_frames': (len(sequences) - len(commit_targets) if policy == 'submission' else len(sequences) - len(targets)) if mode['anchored'] else 0,
            'target_gpu_late_frames': sum(item.get('gpu_ready_before_target_ms', 0) < 0 for item in target_details),
            'target_positive_slots_late_histogram': dict(sorted(target_slots.items(), key=lambda pair: int(pair[0]))),
            'positive_timestamp_fit': refresh_fit(unique),
            'metrics': {key: summary(values) for key, values in sorted(metrics.items())},
            'zero_sequences': zero,
            'duplicate_groups': [{'presented_time': time, 'sequences': sequences} for time, sequences in times.items() if len(sequences) > 1],
            'target_details': target_details,
            'commit_target_details': commit_target_details,
        })
    return {
        'phases': phases,
        'settling': 'Each Viewer refresh_mode interval +5/-2 seconds, intersected with the scene +5/-2 second interval',
        'limitations': [
            'Positive drawable timestamps and CV predictions are driver/API data, not independent physical scanout measurements.',
            'Repeated timestamps share one refresh slot; rates count distinct positive timestamps separately.',
            'predicted_slots_late assumes the current scheduler uses target = predicted refresh minus 2 ms.',
            'commit_target is a CPU submission deadline and is analyzed separately from refresh_target presentation requests.',
            'A negative GPU-ready margin can reflect timestamp inaccuracies; inspect actual ordering and same-clock data.',
            'Viewer phase membership uses gpu_commit time; delivered packet counts use packet arrival time, so boundary counts can differ slightly.',
        ],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = analyze(args.directory)
    output = args.output or args.directory / 'refresh-phase-analysis.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    for phase in result['phases']:
        print(f"phase {phase['phase']} policy={phase['policy']} {phase['seconds']:.2f}s: "
              f"capture {phase['capture_fps']:.2f}, delivered {phase['delivered_fps']:.2f}, "
              f"GPU {phase['gpu_completed_fps']:.2f}, unique {phase['unique_positive_timestamp_fps']:.2f}, "
              f"zero {phase['zero_timestamp_callbacks']}, repeats {phase['repeated_positive_timestamps']}, "
              f"fallback {phase['fallback_frames']}")
