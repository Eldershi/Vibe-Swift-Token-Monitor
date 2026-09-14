#!/usr/bin/env python3
"""Validate native interface resources and interpolation contracts without user data."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/MonitorCore/Resources'

def read_strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))

def main():
    translations = {language: read_strings(RESOURCES / f'{language}.lproj/Localizable.strings')
                    for language in ('en', 'zh-Hans')}
    english, chinese = translations['en'], translations['zh-Hans']
    assert english.keys() == chinese.keys(), 'Language keys differ'
    for key, value in english.items():
        assert value.strip(), f'Empty translation: {key}'
        assert not re.search(r'[\u3400-\u9fff]', value), f'Untranslated English: {key}'
        assert key.count('%@') == value.count('%@') == chinese[key].count('%@'), f'Placeholder mismatch: {key}'
    used = set()
    for path in (ROOT / 'Sources').rglob('*.swift'):
        used.update(re.findall(r'L10n\.text\("([^"\n]*)"', path.read_text()))
    assert not used - english.keys(), f'Missing keys: {used - english.keys()}'
    for key in ('总览', '设备', '模型', '趋势', '用量', '额度', '活动'):
        assert key in english, f'Missing persisted page title: {key}'
    for language in translations:
        assert 'NSLocalNetworkUsageDescription' in read_strings(ROOT / f'Resources/{language}.lproj/InfoPlist.strings')
    print(f'PASS: {len(english)} bilingual keys, interface key coverage, placeholders, and privacy descriptions')

if __name__ == '__main__':
    main()
