"""Inventory active Dart UI sources; discovery is not completion evidence.

Follows relative imports/exports/parts from lib/main.dart, so abandoned backup
files do not inflate the inventory. Modal owner labels are navigation aids and
must be checked against the actual source and flow before acceptance.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLASS = re.compile(r"\bclass\s+(\w+)\s+(?:extends|with|implements)\b")
DEPENDENCY = re.compile(r"\b(?:import|export|part)\s+['\"]([^'\"]+)['\"]")
MODAL = re.compile(r"\b(showDialog|showModalBottomSheet|showSettledDialog|showGeneralDialog)(?:<[^;\n]+?>)?\s*\(")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inventory():
    pending = [ROOT / 'lib/main.dart']
    sources = {}
    while pending:
        path = pending.pop().resolve()
        if path in sources or not path.is_file():
            continue
        text = path.read_text()
        sources[path] = text
        for target in DEPENDENCY.findall(text):
            if ':' not in target:
                dependency = (path.parent / target).resolve()
                if dependency.is_relative_to(ROOT / 'lib'):
                    pending.append(dependency)
    tests = {str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / 'test').glob('*.dart')}
    screens, named, modals = [], [], []
    fingerprint = {}
    for path, text in sorted(sources.items()):
        source = str(path.relative_to(ROOT))
        fingerprint[source] = sha(text.encode())
        classes = list(CLASS.finditer(text))
        for i, match in enumerate(classes):
            name = match.group(1)
            if name.startswith('_'):
                continue
            next_class = classes[i + 1].start() if i + 1 < len(classes) else len(text)
            state = next((m for m in classes if m.group(1) == '_' + name + 'State'), None)
            chunks = text[match.start():next_class]
            if state:
                state_index = classes.index(state)
                end = classes[state_index + 1].start() if state_index + 1 < len(classes) else len(text)
                chunks += text[state.start():end]
            entry = {'name': name, 'source': source, 'line': text.count('\n', 0, match.start()) + 1,
                     'component_sha256': sha(chunks.encode()),
                     'test_reference_candidates': [p for p, body in tests.items() if re.search(r'\b' + name + r'\b', body)],
                     'acceptance': 'unproven_by_inventory'}
            if name.endswith(('Page', 'Tab')) or name == 'MotriIqSplash':
                screens.append(entry)
            elif name.endswith(('Sheet', 'Dialog', 'Gallery')):
                named.append(entry)
        for match in MODAL.finditer(text):
            line = text.count('\n', 0, match.start()) + 1
            before = text[text.rfind('\n', 0, match.start()) + 1:match.start()]
            if re.search(r'\bFuture(?:<.*>)?\s*$', before):
                continue  # helper declaration, rather than an invocation
            owner = next((m.group(1) for m in reversed(classes) if m.start() < match.start()), None)
            modals.append({'source': source, 'line': line, 'api': match.group(1),
                           'nearest_class_candidate': owner, 'acceptance': 'requires_flow_reconciliation'})
    fingerprint.update({str(p.relative_to(ROOT)): sha(p.read_bytes())
                        for p in sorted((ROOT / 'assets/fonts').glob('*')) if p.is_file()})
    return {'status': 'inventory_only_goal_incomplete',
            'scope': 'Active relative dependency closure of lib/main.dart',
            'limits': ['References and nearest class labels locate evidence; they do not prove reachability, state coverage or visual quality.',
                       'Dynamic route builders, transient feedback and anonymous modal variants require manual flow reconciliation.'],
            'counts': {'active_sources': len(sources), 'screens_and_startup': len(screens),
                       'named_supplementary_surfaces': len(named), 'modal_calls': len(modals)},
            'screens': screens, 'named_supplementary_surfaces': named, 'modal_calls': modals,
            'source_and_font_sha256': fingerprint}


if __name__ == '__main__':
    result = inventory()
    (ROOT / 'tool/ui_surface_inventory.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result['counts']))
