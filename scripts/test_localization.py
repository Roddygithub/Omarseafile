#!/usr/bin/env python3
"""Check every shipped locale and execute the real language/interpolation helpers."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = ROOT / "js/locales"
registry = json.loads((DIRECTORY / "registry.json").read_text())
english = json.loads((DIRECTORY / "en.json").read_text())
assert len(registry) == 50
for language in registry:
    strings = json.loads((DIRECTORY / f"{language}.json").read_text())
    assert strings.keys() == english.keys(), language
    for source, translated in strings.items():
        assert isinstance(translated, str) and translated.strip(), (language, source)
        assert sorted(re.findall(r"%\d+", translated)) == sorted(re.findall(r"%\d+", source)), (language, source)
        assert "__" not in translated and source.count("\n") == translated.count("\n"), (language, source)

script = r'''
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync('js/Translation.js', 'utf8'), context);
const registry = JSON.parse(fs.readFileSync('js/locales/registry.json', 'utf8'));
for (const [code, entry] of Object.entries(registry)) {
  assert.equal(context.language(code, 'en_US.UTF-8', registry), code);
  assert.equal(context.language('', entry.locale, registry), code);
}
assert.equal(context.language('fr', 'de_DE.UTF-8', registry), 'fr');
assert.equal(context.language('', 'es_ES.UTF-8', registry), 'es-MX');
assert.equal(context.language('', 'nb_NO.UTF-8', registry), 'no');
assert.equal(context.language('', 'zh_HK.UTF-8', registry), 'zh-TW');
assert.equal(context.language('', 'zh_Hant_TW', registry), 'zh-TW');
assert.equal(context.language('', 'C.UTF-8', registry), 'en');
assert.equal(context.language('../../foo', 'unknown', registry), 'en');
assert.equal(context.language('constructor', 'fr_CA.UTF-8', registry), 'fr');
assert.equal(context.translate({'Open %1': 'Ouvrir %1'}, 'Open %1', ['a%2.txt']), 'Ouvrir a%2.txt');
assert.equal(context.translate({}, 'Missing %1', ['file']), 'Missing file');
assert.equal(context.translate({}, 'constructor'), 'constructor');
assert.equal(context.translate({'Open': ''}, 'Open'), 'Open');
'''
subprocess.run(["node", "-e", script], cwd=ROOT, check=True)
# Compositor selectors, shortcuts and wire values must not go through translation.
for file in ROOT.rglob("*.qml"):
    if "tests" in file.parts or file.name.startswith("test_"):
        continue
    text = file.read_text()
    assert not re.search(r'L10n.t\("(?:dispatch |--|header = |file"|dir"|Authorization")', text), file
    for key in re.finditer(r'L10n.t\(("(?:[^"\\]|\\.)*")', text):
        assert json.loads(key[1]) in english, (file, key[1])
    assert not re.search(r'sequence:\s*L10n.t', text), file
print(f"PASS {len(registry)} complete catalogs, placeholders, locale selection and literal interpolation")
