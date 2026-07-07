/// Bidirectional lookup between CSS named colors and `#rrggbb` hex strings.
///
/// All keys in [colorNameToHex] are lowercase. All hex values use lowercase
/// `#rrggbb` format. [hexToColorName] is the reverse map for serialization.
library;

// ignore_for_file: constant_identifier_names

/// CSS named color → `#rrggbb`.
const Map<String, String> colorNameToHex = {
  'aliceblue': '#f0f8ff',
  'antiquewhite': '#faebd7',
  'aqua': '#00ffff',
  'aquamarine': '#7fffd4',
  'azure': '#f0ffff',
  'beige': '#f5f5dc',
  'bisque': '#ffe4c4',
  'black': '#000000',
  'blanchedalmond': '#ffebcd',
  'blue': '#0000ff',
  'blueviolet': '#8a2be2',
  'brown': '#a52a2a',
  'burlywood': '#deb887',
  'cadetblue': '#5f9ea0',
  'chartreuse': '#7fff00',
  'chocolate': '#d2691e',
  'coral': '#ff7f50',
  'cornflowerblue': '#6495ed',
  'cornsilk': '#fff8dc',
  'crimson': '#dc143c',
  'cyan': '#00ffff',
  'darkblue': '#00008b',
  'darkcyan': '#008b8b',
  'darkgoldenrod': '#b8860b',
  'darkgray': '#a9a9a9',
  'darkgreen': '#006400',
  'darkgrey': '#a9a9a9',
  'darkkhaki': '#bdb76b',
  'darkmagenta': '#8b008b',
  'darkolivegreen': '#556b2f',
  'darkorange': '#ff8c00',
  'darkorchid': '#9932cc',
  'darkred': '#8b0000',
  'darksalmon': '#e9967a',
  'darkseagreen': '#8fbc8f',
  'darkslateblue': '#483d8b',
  'darkslategray': '#2f4f4f',
  'darkslategrey': '#2f4f4f',
  'darkturquoise': '#00ced1',
  'darkviolet': '#9400d3',
  'deeppink': '#ff1493',
  'deepskyblue': '#00bfff',
  'dimgray': '#696969',
  'dimgrey': '#696969',
  'dodgerblue': '#1e90ff',
  'firebrick': '#b22222',
  'floralwhite': '#fffaf0',
  'forestgreen': '#228b22',
  'fuchsia': '#ff00ff',
  'gainsboro': '#dcdcdc',
  'ghostwhite': '#f8f8ff',
  'gold': '#ffd700',
  'goldenrod': '#daa520',
  'gray': '#808080',
  'green': '#008000',
  'greenyellow': '#adff2f',
  'grey': '#808080',
  'honeydew': '#f0fff0',
  'hotpink': '#ff69b4',
  'indianred': '#cd5c5c',
  'indigo': '#4b0082',
  'ivory': '#fffff0',
  'khaki': '#f0e68c',
  'lavender': '#e6e6fa',
  'lavenderblush': '#fff0f5',
  'lawngreen': '#7cfc00',
  'lemonchiffon': '#fffacd',
  'lightblue': '#add8e6',
  'lightcoral': '#f08080',
  'lightcyan': '#e0ffff',
  'lightgoldenrodyellow': '#fafad2',
  'lightgray': '#d3d3d3',
  'lightgreen': '#90ee90',
  'lightgrey': '#d3d3d3',
  'lightpink': '#ffb6c1',
  'lightsalmon': '#ffa07a',
  'lightseagreen': '#20b2aa',
  'lightskyblue': '#87cefa',
  'lightslategray': '#778899',
  'lightslategrey': '#778899',
  'lightsteelblue': '#b0c4de',
  'lightyellow': '#ffffe0',
  'lime': '#00ff00',
  'limegreen': '#32cd32',
  'linen': '#faf0e6',
  'magenta': '#ff00ff',
  'maroon': '#800000',
  'mediumaquamarine': '#66cdaa',
  'mediumblue': '#0000cd',
  'mediumorchid': '#ba55d3',
  'mediumpurple': '#9370db',
  'mediumseagreen': '#3cb371',
  'mediumslateblue': '#7b68ee',
  'mediumspringgreen': '#00fa9a',
  'mediumturquoise': '#48d1cc',
  'mediumvioletred': '#c71585',
  'midnightblue': '#191970',
  'mintcream': '#f5fffa',
  'mistyrose': '#ffe4e1',
  'moccasin': '#ffe4b5',
  'navajowhite': '#ffdead',
  'navy': '#000080',
  'oldlace': '#fdf5e6',
  'olive': '#808000',
  'olivedrab': '#6b8e23',
  'orange': '#ffa500',
  'orangered': '#ff4500',
  'orchid': '#da70d6',
  'palegoldenrod': '#eee8aa',
  'palegreen': '#98fb98',
  'paleturquoise': '#afeeee',
  'palevioletred': '#db7093',
  'papayawhip': '#ffefd5',
  'peachpuff': '#ffdab9',
  'peru': '#cd853f',
  'pink': '#ffc0cb',
  'plum': '#dda0dd',
  'powderblue': '#b0e0e6',
  'purple': '#800080',
  'rebeccapurple': '#663399',
  'red': '#ff0000',
  'rosybrown': '#bc8f8f',
  'royalblue': '#4169e1',
  'saddlebrown': '#8b4513',
  'salmon': '#fa8072',
  'sandybrown': '#f4a460',
  'seagreen': '#2e8b57',
  'seashell': '#fff5ee',
  'sienna': '#a0522d',
  'silver': '#c0c0c0',
  'skyblue': '#87ceeb',
  'slateblue': '#6a5acd',
  'slategray': '#708090',
  'slategrey': '#708090',
  'snow': '#fffafa',
  'springgreen': '#00ff7f',
  'steelblue': '#4682b4',
  'tan': '#d2b48c',
  'teal': '#008080',
  'thistle': '#d8bfd8',
  'tomato': '#ff6347',
  'turquoise': '#40e0d0',
  'violet': '#ee82ee',
  'wheat': '#f5deb3',
  'white': '#ffffff',
  'whitesmoke': '#f5f5f5',
  'yellow': '#ffff00',
  'yellowgreen': '#9acd32',
};

/// `#rrggbb` → CSS named color.
///
/// When multiple names map to the same hex (e.g. `aqua`/`cyan`), only one is
/// kept. The map is built lazily and cached.
final Map<String, String> hexToColorName = _buildReverseMap();

Map<String, String> _buildReverseMap() {
  final map = <String, String>{};
  for (final entry in colorNameToHex.entries) {
    // Last name wins for duplicates — the map is alphabetical so this
    // picks cyan over aqua, darkgrey over darkgray, fuchsia→magenta, etc.
    map[entry.value] = entry.key;
  }
  // Explicit overrides for the duplicate pairs where we prefer the more
  // widely-known name (CMYK standard: cyan, magenta).
  map['#00ffff'] = 'cyan';
  map['#ff00ff'] = 'magenta';
  return map;
}

/// Normalizes a color value from .markdraw input to `#rrggbb` form.
///
/// - CSS named color → `#rrggbb` (case-insensitive)
/// - `#rgb` → `#rrggbb`
/// - `#rrggbb` → pass-through
/// - `transparent` → pass-through
String normalizeColor(String color) {
  // transparent is a special value, pass through
  if (color == 'transparent') return color;

  // Short hex: #rgb → #rrggbb
  if (color.length == 4 && color.startsWith('#')) {
    final r = color[1];
    final g = color[2];
    final b = color[3];
    return '#$r$r$g$g$b$b';
  }

  // Already full hex
  if (color.length == 7 && color.startsWith('#')) {
    return color.toLowerCase();
  }

  // Try named color lookup (case-insensitive)
  final hex = colorNameToHex[color.toLowerCase()];
  if (hex != null) return hex;

  // Unknown — pass through as-is
  return color;
}

/// Formats a `#rrggbb` hex color for .markdraw output in the shortest form.
///
/// 1. Named CSS color if one exists (e.g. `#ff0000` → `red`)
/// 2. Short hex if possible (e.g. `#aabbcc` → `#abc`)
/// 3. Full `#rrggbb` otherwise
String formatColor(String hex) {
  // Try named color
  final name = hexToColorName[hex.toLowerCase()];
  if (name != null) return name;

  // Try short hex: #rrggbb → #rgb if each pair is doubled
  if (hex.length == 7 && hex.startsWith('#')) {
    final lower = hex.toLowerCase();
    if (lower[1] == lower[2] && lower[3] == lower[4] && lower[5] == lower[6]) {
      return '#${lower[1]}${lower[3]}${lower[5]}';
    }
  }

  return hex;
}
