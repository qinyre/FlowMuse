"""python tool/prepare_ui_fonts.py <NotoSansSC[wght].ttf> <OFL.txt>; requires fontTools."""
from pathlib import Path
import hashlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = Path(__file__).resolve().parents[1]
source, license_file = map(Path, sys.argv[1:])
data = source.read_bytes()
assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == 'fb0637bafbcd804fe32152370a1225990745b4bc'
license_data = license_file.read_bytes()
assert hashlib.sha1(b'blob ' + str(len(license_data)).encode() + b'\0' + license_data).hexdigest() == '1c9f43281b8f216c5461fe9ac729afbade7724e4'
characters = set(chr(i) for i in range(0x20, 0x250))
for lead in range(0xA1, 0xF8):
    for trail in range(0xA1, 0xFF):
        try:
            characters.update(bytes([lead, trail]).decode('gb2312'))
        except UnicodeDecodeError:
            continue
for path in (root / 'lib').rglob('*.dart'):
    characters.update(path.read_text(encoding='utf-8'))
characters.update(chr(i) for i in range(0x2000, 0x2070))
characters.update(chr(i) for i in range(0x3000, 0x3040))
characters.update(chr(i) for i in range(0xFF00, 0xFFF0))
codepoints = {ord(c) for c in characters} & set(TTFont(source).getBestCmap())
output = root / 'assets/fonts/ui'
output.mkdir(parents=True, exist_ok=True)
for weight, style in [(400, 'Regular'), (600, 'SemiBold'), (700, 'Bold')]:
    font = instantiateVariableFont(TTFont(source), {'wght': weight}, inplace=True)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_languages = ['*']
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)
    names = {1: 'FlowMuse Sans', 2: style, 3: 'FlowMuseSans-' + style,
             4: 'FlowMuse Sans ' + style, 6: 'FlowMuseSans-' + style,
             16: 'FlowMuse Sans', 17: style}
    for record in font['name'].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    font.recalcTimestamp = False
    assert font['OS/2'].usWeightClass == weight
    target = output / ('FlowMuseSans-' + style + '.ttf')
    font.save(target)
    assert codepoints <= set(TTFont(target).getBestCmap())
    print(target.name, target.stat().st_size, hashlib.sha256(target.read_bytes()).hexdigest())
(output / 'OFL.txt').write_bytes(('\n'.join(line.rstrip() for line in license_data.decode('utf-8').splitlines()) + '\n').encode('utf-8'))
