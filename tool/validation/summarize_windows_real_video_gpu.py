"""Summarize complete real-playback phases without reading credentials/text."""
import argparse
import csv
import datetime as dt
import json
import math
import pathlib
import re
import statistics

root = pathlib.Path(__file__).resolve().parents[2]
folder = root / 'build/validation'
def stamp(s):
    return dt.datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
def load(file):
    return [json.loads(line) for line in file.read_text(encoding='utf-8-sig').splitlines() if line]
def mean(values):
    return statistics.mean(values) if values else None
def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[math.ceil((len(ordered)-1)*fraction)] if ordered else None

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('labels', nargs='+', help='Completed probe labels in build/validation')
args = parser.parse_args()
if any(not re.fullmatch(r'[A-Za-z0-9_-]+', label) for label in args.labels):
    parser.error('Labels must use letters, digits, underscores or hyphens.')
results = []
for label in args.labels:
    pf = folder / f'windows-real-playback-{label}.jsonl'
    gf = folder / f'windows-gpu-engine-{label}.jsonl'
    cf = folder / f'windows-real-clocks-{label}.csv'
    if not pf.exists() or not gf.exists():
        continue
    rows, gpu = load(pf), load(gf)
    if any(r['type'] == 'failed' for r in rows):
        print(f'Excluded failed run: {label}')
        continue
    metadata = next((r for r in rows if r['type'] == 'metadata'), None)
    if metadata is None:
        continue
    luids = {g['luid'] for g in gpu if g['percent'] > 0 and g['engineType'].lower() in ('3d', 'videodecode')}
    if len(luids) != 1:
        raise RuntimeError(f'Unexpected active adapters: {luids}')
    luid = luids.pop()
    # A continuous query preserves its preceding sample and avoids query restarts.
    ticks = sorted({stamp(g['timeUtc']) for g in gpu})
    previous = dict(zip(ticks[1:], ticks[:-1]))
    clocks = []
    if cf.exists():
        with cf.open(encoding='utf-8-sig') as f:
            for c in csv.reader(f):
                if len(c) != 7:
                    continue
                t = dt.datetime.strptime(c[0].strip(), '%Y/%m/%d %H:%M:%S.%f').replace(tzinfo=dt.timezone(dt.timedelta(hours=8))).timestamp()
                clocks.append((t, c[1].strip(), float(c[2].split()[0]), float(c[6].split()[0])))
    for end in [r for r in rows if r['type'] == 'phase-end']:
        stage = end['stage']
        begin = next(r for r in rows if r['type'] == 'phase-start' and r['stage'] == stage)
        start_t, end_t = stamp(begin['timeUtc']), stamp(end['timeUtc'])
        samples = [r for r in rows if r['type'] == 'sample' and r['stage'] == stage]
        sgpu = [g for g in gpu if g['luid'] == luid and start_t <= previous.get(stamp(g['timeUtc']), 0) and stamp(g['timeUtc']) <= end_t]
        g3d = [g['percent'] for g in sgpu if g['engineType'].lower() == '3d']
        decode = [g['percent'] for g in sgpu if g['engineType'].lower() == 'videodecode']
        gticks = sorted({stamp(g['timeUtc']) for g in sgpu})
        cs = [c for c in clocks if start_t <= c[0] <= end_t]
        first, last = samples[0], samples[-1]
        paints = last['imagePaints'] - first['imagePaints']
        ui = [v/1000 for s in samples for v in s['uiUs']]
        raster = [v/1000 for s in samples for v in s['rasterUs']]
        entry = {
            'label': label, 'stage': stage, 'bvid': metadata['bvid'],
            'opacity': metadata['opacity'],
            'actualQuality': metadata['actualQuality'], 'release': metadata['release'],
            'seconds': end['elapsedMs']/1000, 'playbackSamples': len(samples),
            'gpuPoints': len(g3d), 'gpuSpanSeconds': gticks[-1] - previous[gticks[0]] if gticks else 0,
            'gpuIntervalMean': mean([t-previous[t] for t in gticks]),
            'luid': luid, '3dMean': mean(g3d), '3dP95': percentile(g3d,.95), 'decodeMean': mean(decode),
            'dartFps': mean([s['dartFrames'] for s in samples]),
            'visibleMean': mean([s['visible'] for s in samples]), 'visibleMax': max(s['visible'] for s in samples),
            'clockMean': mean([c[2] for c in cs]), 'clockMedian': percentile([c[2] for c in cs],.5),
            'pstates': sorted({c[1] for c in cs}), 'watts': mean([c[3] for c in cs]),
            'uiP95ms': percentile(ui,.95), 'rasterP95ms': percentile(raster,.95), 'rasterP99ms': percentile(raster,.99),
            'rasterPeakMiB': max(s['rasterBytes'] for s in samples)/(1024*1024),
            'cacheHitPercent': (last['cacheHits']-first['cacheHits'])/paints*100 if paints else None,
            'directPaints': last['directPaints']-first['directPaints'],
            'hwdec': sorted({s['hwdec'] for s in samples}),
            'decoded': sorted({tuple(s['decoded']) for s in samples}),
            'output': sorted({tuple(s['output']) for s in samples}),
            'surface': sorted({tuple(s['surfaceLogical']) for s in samples}),
            'viewPhysical': sorted({tuple(s['viewPhysical']) for s in samples}),
            'dpr': sorted({s['dpr'] for s in samples}),
            'rate': sorted({s['rate'] for s in samples}),
            'frameDrops': sorted({s['frameDrops'] for s in samples}),
            'decoderDrops': sorted({s['decoderDrops'] for s in samples}),
            'maxAvsyncMs': max(abs(s['avsyncSeconds'] or 0)*1000 for s in samples),
            'buffering': any(s['buffering'] or s['seeking'] for s in samples),
            'errors': max(s['errors'] for s in samples),
            'startPositionMs': first['positionMs'], 'endPositionMs': last['positionMs'],
        }
        active_gpu, idle_gpu = [], []
        for g in sgpu:
            if g['engineType'].lower() != '3d':
                continue
            t = stamp(g['timeUtc'])
            i = next((i for i, s in enumerate(samples) if stamp(s['timeUtc']) >= t), None)
            if i is None or i == 0:
                continue
            before, after = samples[i-1], samples[i]
            if before['visible'] > 0 and after['visible'] > 0:
                active_gpu.append(g['percent'])
            if before['visible'] == 0 and after['visible'] == 0:
                idle_gpu.append(g['percent'])
        entry['activeGpuPoints'] = len(active_gpu)
        entry['active3dMean'] = mean(active_gpu)
        entry['activeDartFps'] = mean([s['dartFrames'] for i,s in enumerate(samples) if i>0 and samples[i-1]['visible']>0 and s['visible']>0])
        entry['activeTextPaintsPerSecond'] = mean([s['imagePaints']-samples[i-1]['imagePaints'] for i,s in enumerate(samples) if i>0 and samples[i-1]['visible']>0 and s['visible']>0])
        entry['idleGpuPoints'] = len(idle_gpu)
        entry['idle3dMean'] = mean(idle_gpu)
        results.append(entry)
        print(f"{label:14} {stage:14} {entry['seconds']:.3f}s {len(g3d)} GPU points: "
              f"3D={entry['3dMean']:.2f}% fps={entry['dartFps']:.1f} visible={entry['visibleMean']:.1f} "
              f"clock={entry['clockMean']} output={entry['output']} drops={entry['frameDrops']}/{entry['decoderDrops']}")
(folder/'windows-real-video-summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
