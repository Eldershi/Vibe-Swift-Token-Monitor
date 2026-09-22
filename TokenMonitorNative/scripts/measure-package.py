#!/usr/bin/env python3
"""Measure actual app/ZIP bytes, separating runtime, UI and resources."""
import argparse
import json
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
parser.add_argument('--baseline', type=Path)
args = parser.parse_args()


def measure(archive):
    with zipfile.ZipFile(archive) as bundle:
        files = [entry for entry in bundle.infolist() if not entry.is_dir()]
        groups = {}
        for entry in files:
            relative = entry.filename.split('/Contents/', 1)[-1]
            if '/runtime/' in relative:
                group = 'Node runtime'
            elif '/@tokscale/' in relative:
                group = 'Tokscale'
            elif relative.startswith('Resources/Backend/'):
                group = 'Backend JS and dependencies'
            elif relative.startswith('Frameworks/'):
                group = 'Sparkle'
            elif relative.startswith('MacOS/'):
                group = 'Native executables'
            else:
                group = 'UI assets, localization and metadata'
            groups[group] = groups.get(group, 0) + entry.file_size
        return {'zipBytes': archive.stat().st_size, 'appBytes': sum(e.file_size for e in files), 'groups': groups}


result = {'current': measure(args.archive)}
if args.baseline:
    result['baseline'] = measure(args.baseline)
    result['reductionPercent'] = {key: round(100 * (1 - result['current'][key] / result['baseline'][key]), 2) for key in ['zipBytes', 'appBytes']}
print(json.dumps(result, indent=2))
