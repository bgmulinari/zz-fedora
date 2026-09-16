"""Behavior checks for the small segment-foreground contrast adjustment."""
from pathlib import Path
import runpy
import sys
import tomllib

root = Path(sys.argv[1])
helper = runpy.run_path(str(root / 'dotfiles/dms/.local/bin/zz-sync-starship-palette'))
adjust = helper['readable_foregrounds']
contrast = helper['contrast']
assert contrast('#000000', '#ffffff') == 21
assert contrast('#777777', '#777777') == 1

seed = tomllib.loads((root / 'templates/starship.toml').read_text())
colors = seed['palettes']['zz']
before = colors.copy()
adjust(colors)
assert colors == before, 'Mocha foregrounds should remain unchanged'

for background, expected in [('#003e71', '#e0e2e8'), ('#f5f5f5', '#191c20')]:
    palette = {'mauve': background, 'base': '#191c20', 'text': '#e0e2e8'}
    original = palette.copy()
    adjust(palette)
    assert palette['on_mauve'] == expected, palette
    assert all(palette[key] == value for key, value in original.items())
    assert contrast(palette['on_mauve'], background) >= 4.5

# All sections share the same pair, even at midtones where neither reaches
# 4.5:1. Reversing the pair exercises light themes too.
backgrounds = dict(zip(('surface0', 'peach', 'green', 'teal', 'blue', 'mauve'),
                       ('#003e71', '#f5f5f5', '#777777', '#707070', '#111111', '#eeeeee')))
for text, base in [('#e0e2e8', '#191c20'), ('#191c20', '#e0e2e8')]:
    palette = dict(backgrounds, text=text, base=base, on_mauve='#ffffee')
    adjust(palette)
    used = {palette['on_' + name] for name in backgrounds}
    assert used == {text, base}, used
    for name, background in backgrounds.items():
        chosen = palette['on_' + name]
        assert contrast(chosen, background) == max(contrast(text, background), contrast(base, background))
        assert palette[name] == background
    before = palette.copy()
    adjust(palette)
    assert palette == before, 'Repeated synchronization must be stable'

print('Foreground checks passed')
