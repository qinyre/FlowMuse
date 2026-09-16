// R9 offline evaluation. Standard library only; never invokes a provider.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

typedef Row = Map<String, dynamic>;

Never invalid(String message) => throw FormatException(message);
Row object(Object? value, String at) =>
    value is Row ? value : invalid('$at: object required');
List<dynamic> array(Object? value, String at) =>
    value is List ? value : invalid('$at: array required');
String string(Object? value, String at, {bool empty = false}) =>
    value is String && (empty || value.trim().isNotEmpty)
    ? value
    : invalid('$at: string required');
bool boolean(Object? value, String at) =>
    value is bool ? value : invalid('$at: boolean required');
List<String> strings(Object? value, String at) =>
    array(value, at).map((v) => string(v, at)).toList();
List<Row> objects(Object? value, String at) =>
    array(value, at).map((v) => object(v, at)).toList();

// Keep case, digits and punctuation; ignore whitespace so a region split does
// not introduce an artificial character error at the join boundary.
String normalize(String text) =>
    text.replaceAll(RegExp(r'\s+', unicode: true), '');
String withoutPunctuation(String text) => normalize(text).replaceAll(
  RegExp(
    r'''[!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~，。！？、；：“”‘’（）【】《》〈〉…—·]''',
    unicode: true,
  ),
  '',
);
int distance(String reference, String prediction) {
  final a = reference.runes.toList(), b = prediction.runes.toList();
  var prior = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final next = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      next[j + 1] = math.min(
        math.min(next[j] + 1, prior[j + 1] + 1),
        prior[j] + (a[i] == b[j] ? 0 : 1),
      );
    }
    prior = next;
  }
  return prior.last;
}

List<Row> readRows(String path) {
  final lines = const LineSplitter().convert(File(path).readAsStringSync());
  return [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].trim().isNotEmpty)
        object(jsonDecode(lines[i]), '$path:${i + 1}'),
  ];
}

Map<String, Row> indexRows(List<Row> rows) {
  final result = <String, Row>{};
  for (final row in rows) {
    final id = string(row['caseId'], 'caseId');
    if (result.containsKey(id)) invalid('duplicate caseId: $id');
    result[id] = row;
  }
  return result;
}

void validateRegions(Row row, bool truth) {
  final ids = <String>{};
  for (final region in objects(row['regions'], 'regions')) {
    final id = string(region[truth ? 'evalRegionId' : 'regionId'], 'region id');
    if (!ids.add(id)) invalid('duplicate region id: $id');
    string(region[truth ? 'referenceText' : 'recognizedText'], id, empty: true);
    boolean(region[truth ? 'legible' : 'converted'], id);
    if (!truth) {
      final status = string(region['status'], 'status');
      if (!{
        'recognized',
        'uncertain',
        'unreadable',
        'nonText',
        'preserved',
      }.contains(status)) {
        invalid('unknown region status');
      }
      if (region['converted'] == true && status != 'recognized')
        invalid('converted region is not recognized');
    }
    final refs = strings(region['sourceRefs'], 'sourceRefs');
    if (refs.toSet().length != refs.length) invalid('duplicate sourceRefs');
    final bounds = object(region['bounds'], 'bounds');
    for (final key in ['left', 'top', 'width', 'height']) {
      final value = bounds[key];
      if (value is! num ||
          !value.isFinite ||
          ((key == 'width' || key == 'height') && value <= 0))
        invalid('invalid bounds.$key');
    }
  }
}

List<List<String>> lists(Row row) => array(
  row['orderedLists'],
  'orderedLists',
).map((items) => strings(items, 'list items').map(normalize).toList()).toList();

void validateTruth(Row row) {
  string(row['sourceRef'], 'sourceRef');
  string(row['contentFingerprint'], 'contentFingerprint');
  final text = string(row['referenceText'], 'referenceText', empty: true);
  if (!{'dev', 'holdout'}.contains(row['split'])) invalid('invalid split');
  if (!{'unreviewed', 'aiDraft', 'humanVerified'}.contains(row['reviewStatus']))
    invalid('invalid reviewStatus');
  var previousEnd = 0;
  for (final range in objects(row['uncertainRanges'], 'uncertainRanges')) {
    final start = range['start'], end = range['end'];
    if (start is! int ||
        end is! int ||
        start < previousEnd ||
        end <= start ||
        end > text.runes.length) {
      invalid('invalid or overlapping uncertainRanges');
    }
    previousEnd = end;
  }
  validateRegions(row, true);
  final expected = object(row['expect'], 'expect');
  lists(expected);
  if (expected.containsKey('title'))
    string(expected['title'], 'title', empty: true);
}

void validatePredictions(
  Map<String, Row> predictions,
  Map<String, Row> truth,
  String pipeline,
) {
  for (final entry in predictions.entries) {
    final row = entry.value, reference = truth[entry.key];
    if (reference == null) invalid('unknown prediction caseId: ${entry.key}');
    if (row['pipeline'] != pipeline) invalid('pipeline mismatch');
    if (row['contentFingerprint'] != reference['contentFingerprint'])
      invalid('fingerprint mismatch: ${entry.key}');
    string(row['model'], 'model');
    string(row['recognizedText'], 'recognizedText', empty: true);
    boolean(row['converted'], 'converted');
    boolean(row['preserved'], 'preserved');
    validateRegions(row, false);
    final structure = object(row['structure'], 'structure');
    lists(structure);
    if (structure.containsKey('title'))
      string(structure['title'], 'title', empty: true);
  }
}

double overlap(Row a, Row b, {required bool sourceRefs}) {
  if (sourceRefs) {
    final x = strings(a['sourceRefs'], 'sourceRefs').toSet();
    final y = strings(b['sourceRefs'], 'sourceRefs').toSet();
    return x.union(y).isEmpty
        ? 0
        : x.intersection(y).length / x.union(y).length;
  }
  final x = a['bounds'] as Row, y = b['bounds'] as Row;
  final width = math.max<num>(
    0,
    math.min<num>(x['left'] + x['width'], y['left'] + y['width']) -
        math.max<num>(x['left'], y['left']),
  );
  final height = math.max<num>(
    0,
    math.min<num>(x['top'] + x['height'], y['top'] + y['height']) -
        math.max<num>(x['top'], y['top']),
  );
  final intersection = width * height;
  return intersection /
      (x['width'] * x['height'] + y['width'] * y['height'] - intersection);
}

int readingOrder(Row a, Row b) {
  final top = (a['bounds']['top'] as num).compareTo(b['bounds']['top'] as num);
  if (top != 0) return top;
  final left = (a['bounds']['left'] as num).compareTo(
    b['bounds']['left'] as num,
  );
  if (left != 0) return left;
  return '${a['regionId'] ?? a['evalRegionId']}'.compareTo(
    '${b['regionId'] ?? b['evalRegionId']}',
  );
}

class Counts {
  final values = <String, int>{};
  void add(String key, [int value = 1]) =>
      values.update(key, (n) => n + value, ifAbsent: () => value);
  int operator [](String key) => values[key] ?? 0;
  void text(String prefix, String reference, String prediction) {
    final r = normalize(reference), p = normalize(prediction);
    add('${prefix}Chars', r.runes.length);
    add('${prefix}Edits', distance(r, p));
    if (r.isEmpty) {
      add('${prefix}EmptyReferences');
      if (p.isNotEmpty) add('${prefix}EmptyReferenceErrors');
    }
  }

  void merge(Counts other) => other.values.forEach(add);
  double? ratio(String numerator, String denominator) =>
      this[denominator] == 0 ? null : this[numerator] / this[denominator];
  Row report() => {
    ...values,
    'cer': ratio('pageEdits', 'pageChars'),
    'cerWithoutPunctuation': ratio('noPunctuationEdits', 'noPunctuationChars'),
    'legibleCer': ratio('legibleEdits', 'legibleChars'),
    'convertedCer': ratio('convertedEdits', 'convertedChars'),
    'conversionCoverage': ratio('coveredRegions', 'legibleRegions'),
    'errorConversionRate': ratio('wrongConvertedRegions', 'convertedRegions'),
    'severeErrorConversionRate': ratio(
      'severeConvertedRegions',
      'convertedRegions',
    ),
    'preservedRegionRate': ratio(
      'preservedPredictionRegions',
      'predictionRegions',
    ),
  };
}

// Explicit mappings are truth-owned and pipeline-scoped:
// explicitAlignment: {v1: {runtimeId: [evalId,...]}, v3: {...}}.
({Counts counts, Row details}) pageMetrics(
  Row truth,
  Row? prediction,
  String pipeline,
) {
  final c = Counts()..add('pages');
  final reference = truth['referenceText'] as String;
  final text = prediction?['recognizedText'] as String? ?? '';
  c.text('page', reference, text);
  c.text(
    'noPunctuation',
    withoutPunctuation(reference),
    withoutPunctuation(text),
  );
  final digits = RegExp(r'[0-9０-９]+(?:[.．][0-9０-９]+)?');
  if (jsonEncode(digits.allMatches(reference).map((m) => m[0]).toList()) !=
      jsonEncode(digits.allMatches(text).map((m) => m[0]).toList()))
    c.add('digitMismatchPages');
  if (prediction == null) c.add('missingPredictionPages');
  final expected = truth['expect'] as Row;
  final structure = prediction?['structure'] as Row? ?? {'orderedLists': []};
  final expectedLists = lists(expected), predictedLists = lists(structure);
  if (jsonEncode(expectedLists.map((l) => l.length).toList()) !=
      jsonEncode(predictedLists.map((l) => l.length).toList()))
    c.add('listCountMismatchPages');
  if (jsonEncode(expectedLists) != jsonEncode(predictedLists))
    c.add('listOrderOrTextMismatchPages');
  if (expected.containsKey('title') &&
      normalize(expected['title']) !=
          normalize(structure['title'] as String? ?? ''))
    c.add('titleMismatchPages');
  final refs = objects(truth['regions'], 'regions')..sort(readingOrder);
  final preds =
      prediction == null ? <Row>[] : objects(prediction['regions'], 'regions')
        ..sort(readingOrder);
  c.add('legibleRegions', refs.where((r) => r['legible'] == true).length);
  c.add('predictionRegions', preds.length);
  c.add(
    'preservedPredictionRegions',
    preds.where((p) => p['converted'] == false).length,
  );
  if (prediction?['preserved'] == true) c.add('preservedPages');
  if (prediction?['converted'] == true && prediction?['preserved'] == true)
    c.add('partialPages');
  final refById = {for (final r in refs) r['evalRegionId'] as String: r};
  final mappings = <String, Set<String>>{};
  final ambiguous = <String>[];
  final unmatched = <String>[];
  final explicitRoot = truth['explicitAlignment'] == null
      ? <String, dynamic>{}
      : object(truth['explicitAlignment'], 'explicitAlignment');
  if (explicitRoot.keys.any((k) => k != 'v1' && k != 'v3'))
    invalid('explicitAlignment must be pipeline-scoped');
  final explicit = explicitRoot[pipeline] == null
      ? <String, dynamic>{}
      : object(explicitRoot[pipeline], 'explicitAlignment.$pipeline');
  if (prediction != null &&
      explicit.keys.any((id) => !preds.any((p) => p['regionId'] == id)))
    invalid('explicitAlignment references unknown prediction');
  for (final p in preds) {
    final id = p['regionId'] as String;
    if (explicit.containsKey(id)) {
      final targets = strings(explicit[id], 'explicit targets');
      if (targets.isEmpty ||
          targets.toSet().length != targets.length ||
          targets.any((id) => !refById.containsKey(id)))
        invalid('invalid explicit targets');
      mappings[id] = targets.toSet();
      continue;
    }
    // Prediction-side IDs are not authoritative alignment evidence.
    var scored = [(forRef: '', score: 0.0)];
    for (final byRefs in [true, false]) {
      scored = [
        for (final r in refs)
          (
            forRef: r['evalRegionId'] as String,
            score: overlap(p, r, sourceRefs: byRefs),
          ),
      ]..sort((a, b) => b.score.compareTo(a.score));
      if (scored.isNotEmpty && scored.first.score >= 0.5) break;
    }
    if (scored.isEmpty || scored.first.score < 0.5) {
      unmatched.add(id);
      continue;
    }
    final best = scored
        .where((r) => (r.score - scored.first.score).abs() < 1e-9)
        .toList();
    if (best.length != 1) {
      ambiguous.add(id);
      continue;
    }
    mappings[id] = {best.single.forRef};
  }
  // Connected alignment groups: merged/split text is counted once per group.
  final pending = mappings.keys.toSet();
  final alignedRefs = <String>{};
  final groups = <Row>[];
  while (pending.isNotEmpty) {
    final pids = {pending.first};
    final rids = <String>{...mappings[pending.first]!};
    var changed = true;
    while (changed) {
      changed = false;
      for (final id in pending) {
        if (!pids.contains(id) && mappings[id]!.intersection(rids).isNotEmpty) {
          pids.add(id);
          rids.addAll(mappings[id]!);
          changed = true;
        }
      }
    }
    pending.removeAll(pids);
    alignedRefs.addAll(rids);
    final rs = refs.where((r) => rids.contains(r['evalRegionId'])).toList();
    final ps = preds.where((p) => pids.contains(p['regionId'])).toList();
    final rtext = rs.map((r) => r['referenceText']).join('\n');
    final ptext = ps.map((p) => p['recognizedText']).join('\n');
    final edits = distance(normalize(rtext), normalize(ptext));
    final legible = rs.every((r) => r['legible'] == true);
    final converted = ps.every((p) => p['converted'] == true);
    if (legible) {
      c.text('legible', rtext, ptext);
      if (converted && (rs.length == 1 || edits == 0))
        c.add('coveredRegions', rs.length);
    }
    if (converted) {
      c.text('converted', rtext, ptext);
      c.add('convertedRegions', rs.length);
      if (edits > 0) {
        c.add('wrongConvertedRegions', rs.length);
        final length = normalize(rtext).runes.length;
        if (length == 0 || edits / length > 0.2)
          c.add('severeConvertedRegions', rs.length);
      }
    }
    if (!legible && rs.any((r) => r['legible'] == true))
      c.add('mixedLegibilityGroups');
    groups.add({
      'predictionIds': pids.toList()..sort(),
      'referenceIds': rids.toList()..sort(),
      'edits': edits,
      'converted': converted,
    });
  }
  for (final r in refs.where((r) => !alignedRefs.contains(r['evalRegionId']))) {
    c.add('unmatchedTruthRegions');
    if (r['legible'] == true) c.text('legible', r['referenceText'], '');
  }
  for (final p in preds.where((p) => !mappings.containsKey(p['regionId']))) {
    c.text('legible', '', p['recognizedText']);
    if (p['converted'] == true) {
      c.text('converted', '', p['recognizedText']);
      c.add('extraConvertedRegions');
    }
  }
  c.add('ambiguousPredictionRegions', ambiguous.length);
  c.add('unmatchedPredictionRegions', unmatched.length);
  if (c['legibleEdits'] == 0 &&
      (c['listOrderOrTextMismatchPages'] > 0 || c['titleMismatchPages'] > 0))
    c.add('structureOnlyFailurePages');
  return (
    counts: c,
    details: {
      'metrics': c.report(),
      'alignmentGroups': groups,
      'ambiguousPredictionIds': ambiguous,
      'unmatchedPredictionIds': unmatched,
      'model': prediction?['model'],
      'missingPrediction': prediction == null,
    },
  );
}

Row evaluate(List<Row> truthRows, List<Row> v1Rows, List<Row> v3Rows) {
  final truth = indexRows(truthRows),
      v1 = indexRows(v1Rows),
      v3 = indexRows(v3Rows);
  for (final row in truth.values) {
    validateTruth(row);
  }
  validatePredictions(v1, truth, 'v1');
  validatePredictions(v3, truth, 'v3');
  final fingerprints = <String>{};
  for (final row in truth.values) {
    if (!fingerprints.add(row['contentFingerprint']))
      invalid('duplicate input fingerprint (split leakage)');
  }
  final totals = {
    for (final split in ['dev', 'holdout', 'all'])
      split: {
        for (final p in ['v1', 'v3']) p: Counts(),
      },
  };
  final pages = <Row>[];
  var uncertainChars = 0, unverifiedPages = 0;
  for (final id in truth.keys.toList()..sort()) {
    final row = truth[id]!;
    if (row['reviewStatus'] != 'humanVerified') unverifiedPages++;
    for (final range in objects(row['uncertainRanges'], 'uncertainRanges')) {
      uncertainChars += (range['end'] as int) - (range['start'] as int);
    }
    final page = <String, dynamic>{'caseId': id, 'split': row['split']};
    for (final pipeline in ['v1', 'v3']) {
      final result = pageMetrics(
        row,
        (pipeline == 'v1' ? v1 : v3)[id],
        pipeline,
      );
      totals[row['split']]![pipeline]!.merge(result.counts);
      totals['all']![pipeline]!.merge(result.counts);
      page[pipeline] = result.details;
    }
    pages.add(page);
  }
  final old = totals['holdout']!['v1']!, current = totals['holdout']!['v3']!;
  final oldCer = old.ratio('pageEdits', 'pageChars'),
      cer = current.ratio('pageEdits', 'pageChars');
  final coverage = current.ratio('coveredRegions', 'legibleRegions');
  final ready =
      truth.length >= 20 &&
      unverifiedPages == 0 &&
      uncertainChars == 0 &&
      totals['dev']!['v3']!['pages'] > 0 &&
      current['pages'] > 0 &&
      current['mixedLegibilityGroups'] == 0;
  final checks = <String, bool>{
    'cerAtMost5Percent':
        cer != null && cer <= 0.05 && current['pageEmptyReferenceErrors'] == 0,
    'relativeReduction20PercentWhenV1Above5Percent':
        oldCer != null &&
        cer != null &&
        (oldCer <= 0.05 || cer <= oldCer * 0.8),
    'conversionCoverageAtLeast90Percent': coverage != null && coverage >= 0.9,
    'digitsExact': current['digitMismatchPages'] == 0,
    'listsAndTitleExact':
        current['listOrderOrTextMismatchPages'] == 0 &&
        current['titleMismatchPages'] == 0,
    'noAmbiguousOrExtraRegions':
        current['ambiguousPredictionRegions'] == 0 &&
        current['unmatchedPredictionRegions'] == 0,
    'pairedHoldoutPredictionsPresent':
        current['missingPredictionPages'] == 0 &&
        old['missingPredictionPages'] == 0,
  };
  return {
    'schemaVersion': 1,
    'exitCode': !ready
        ? 2
        : checks.values.every((v) => v)
        ? 0
        : 1,
    'truthReady': ready,
    'truthPages': truth.length,
    'unverifiedPages': unverifiedPages,
    'uncertainCodePoints': uncertainChars,
    'uncertainCodePointRatio': totals['all']!['v3']!['pageChars'] == 0
        ? null
        : uncertainChars /
              truth.values.fold<int>(
                0,
                (n, r) => n + (r['referenceText'] as String).runes.length,
              ),
    'normalization':
        'case/punctuation retained; whitespace ignored; Unicode code points',
    'thresholdSplit': 'holdout',
    'checks': checks,
    'summary': {
      for (final split in totals.keys)
        split: {
          for (final p in ['v1', 'v3']) p: totals[split]![p]!.report(),
        },
    },
    'pages': pages,
    'deviceValidation': 'not-performed',
    'performanceValidation': 'not-measured-by-offline-evaluator',
  };
}

void main(List<String> args) {
  try {
    if (args.length == 1 && args.single == '--self-test') {
      selfTest();
      return;
    }
    final options = <String, String>{};
    for (var i = 0; i < args.length; i += 2) {
      if (i + 1 >= args.length ||
          !['--truth', '--v1', '--v3', '--out'].contains(args[i]) ||
          options.containsKey(args[i]))
        invalid('invalid arguments');
      options[args[i]] = args[i + 1];
    }
    if (options.length != 4)
      invalid(
        'usage: --self-test OR --truth cases.jsonl --v1 v1.jsonl --v3 v3.jsonl --out report.json',
      );
    final output = File(options['--out']!);
    String canonical(File file) {
      final path = file.existsSync()
          ? file.resolveSymbolicLinksSync()
          : file.absolute.uri.normalizePath().toFilePath();
      return Platform.isWindows ? path.toLowerCase() : path;
    }

    if ([
      '--truth',
      '--v1',
      '--v3',
    ].any((key) => canonical(File(options[key]!)) == canonical(output)))
      invalid('output must not overwrite input');
    final report = evaluate(
      readRows(options['--truth']!),
      readRows(options['--v1']!),
      readRows(options['--v3']!),
    );
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    exitCode = report['exitCode'] as int;
    stdout.writeln(
      'evaluation exit=$exitCode; pages=${report['truthPages']}; report=${output.path}',
    );
  } on FormatException catch (error) {
    stderr.writeln('invalid evaluation input: ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('evaluation file unavailable: ${error.path}');
    exitCode = 2;
  }
}

void selfTest() {
  var checks = 0;
  void check(bool condition, String name) {
    if (!condition) throw StateError('self-test failed: $name');
    checks++;
  }

  Row region(
    String id,
    String text,
    List<String> refs, {
    bool truth = true,
    double left = 0,
  }) => {
    truth ? 'evalRegionId' : 'regionId': id,
    truth ? 'referenceText' : 'recognizedText': text,
    if (truth)
      'legible': true
    else ...{
      'converted': true,
      'status': 'recognized',
    },
    'sourceRefs': refs,
    'bounds': {'left': left, 'top': 0, 'width': 10, 'height': 10},
  };
  Row truth(String id) => {
    'caseId': id,
    'split': id == '0' ? 'dev' : 'holdout',
    'sourceRef': 'synthetic-self-test/$id',
    'contentFingerprint': 'synthetic-$id',
    'referenceText': '甲1',
    'reviewStatus': 'humanVerified',
    'uncertainRanges': [],
    'regions': [
      region('eval', '甲1', ['s']),
    ],
    'expect': {'orderedLists': []},
  };
  Row prediction(String id, String pipeline) => {
    'caseId': id,
    'contentFingerprint': 'synthetic-$id',
    'pipeline': pipeline,
    'model': 'synthetic-self-test-not-provider',
    'recognizedText': '甲1',
    'converted': true,
    'preserved': false,
    'regions': [
      region('runtime', '甲1', ['s'], truth: false),
    ],
    'structure': {'orderedLists': []},
  };
  for (final sample in [
    ('甲', '甲', 0),
    ('甲', '乙', 1),
    ('甲', '甲乙', 1),
    ('甲乙', '甲', 1),
    ('', '乙', 1),
    ('𠮷😀', '𠮷', 1),
  ]) {
    check(distance(sample.$1, sample.$2) == sample.$3, 'edit distance $sample');
  }
  check(
    normalize(' 甲\n乙 ') == '甲乙' && withoutPunctuation('甲，乙。') == '甲乙',
    'normalization',
  );
  final t = [for (var i = 0; i < 20; i++) truth('$i')];
  final a = [for (var i = 0; i < 20; i++) prediction('$i', 'v1')];
  final b = [for (var i = 0; i < 20; i++) prediction('$i', 'v3')];
  check(evaluate(t, a, b)['exitCode'] == 0, 'all correct');
  // Exercise the actual CLI/JSONL/exit-code boundary with disposable data only.
  // These are synthetic unit inputs, never written to the evidence directory.
  final temp = Directory.systemTemp.createTempSync(
    'flowmuse-recognition-eval-test-',
  );
  try {
    final truthFile = File('${temp.path}/synthetic-truth.jsonl');
    final v1File = File('${temp.path}/synthetic-v1.jsonl');
    final v3File = File('${temp.path}/synthetic-v3.jsonl');
    final reportFile = File('${temp.path}/synthetic-report.json');
    void write(File file, List<Row> rows) =>
        file.writeAsStringSync(rows.map(jsonEncode).join('\n'));
    write(truthFile, t);
    write(v1File, a);
    write(v3File, b);
    final command = [
      Platform.script.toFilePath(),
      '--truth',
      truthFile.path,
      '--v1',
      v1File.path,
      '--v3',
      v3File.path,
      '--out',
      reportFile.path,
    ];
    int run() => Process.runSync(Platform.resolvedExecutable, command).exitCode;
    check(
      run() == 0 && jsonDecode(reportFile.readAsStringSync())['exitCode'] == 0,
      'CLI success 0',
    );
    final originalReport = reportFile.readAsStringSync();
    check(
      run() == 0 && originalReport == reportFile.readAsStringSync(),
      'deterministic report',
    );
    write(v3File, b.sublist(0, 19));
    check(run() == 1, 'CLI threshold failure 1');
    write(v3File, b);
    write(truthFile, [
      for (final row in t) {...row, 'reviewStatus': 'aiDraft'},
    ]);
    check(run() == 2, 'CLI unverified truth 2');
    truthFile.writeAsStringSync('{broken json');
    check(run() == 2, 'CLI malformed JSON 2');
    truthFile.deleteSync();
    check(run() == 2, 'CLI missing input 2');
  } finally {
    for (final file in temp.listSync().whereType<File>()) {
      file.deleteSync();
    }
    temp.deleteSync();
  }
  check(
    evaluate(t, a, b.sublist(0, 19))['exitCode'] == 1,
    'missing prediction fails',
  );
  final missing = pageMetrics(t[1], null, 'v3').counts;
  check(
    missing['pageEdits'] == 2 && missing['missingPredictionPages'] == 1,
    'missing is deletion',
  );
  final before = b[0]['recognizedText'];
  b[0]['recognizedText'] = '坏的开发样例';
  check(evaluate(t, a, b)['exitCode'] == 0, 'dev cannot change holdout gate');
  b[0]['recognizedText'] = before;
  t[1]['reviewStatus'] = 'aiDraft';
  check(evaluate(t, a, b)['exitCode'] == 2, 'AI draft is not truth');
  t[1]['reviewStatus'] = 'humanVerified';
  void rejects(void Function() action, String name) {
    try {
      action();
    } on FormatException {
      checks++;
      return;
    }
    throw StateError('accepted invalid $name');
  }

  rejects(() => indexRows([t.first, t.first]), 'duplicate ID');
  final malformed = truth('bad')..['regions'] = 'not-an-array';
  rejects(() => validateTruth(malformed), 'malformed regions');
  final uncertain = truth('u')
    ..['uncertainRanges'] = [
      {'start': 0, 'end': 99},
    ];
  rejects(() => validateTruth(uncertain), 'invalid uncertain ranges');
  t[1]['uncertainRanges'] = [
    {'start': 0, 'end': 1},
  ];
  check(evaluate(t, a, b)['exitCode'] == 2, 'unresolved reference cannot pass');
  t[1]['uncertainRanges'] = <Row>[];
  final weighted = Counts()
    ..text('page', '甲', '乙')
    ..text('page', '甲' * 99, '甲' * 99);
  check(weighted.report()['cer'] == 0.01, 'corpus CER weighted by characters');
  final empty = Counts()..text('page', '', '多余');
  check(
    empty['pageEdits'] == 2 &&
        empty['pageEmptyReferenceErrors'] == 1 &&
        empty.report()['cer'] == null,
    'empty reference retained',
  );
  final listTruth = truth('list')
    ..['expect'] = {
      'orderedLists': [
        ['甲', '乙'],
      ],
    };
  final listPred = prediction('list', 'v3')
    ..['structure'] = {
      'orderedLists': [
        ['乙', '甲'],
      ],
    };
  check(
    pageMetrics(
          listTruth,
          listPred,
          'v3',
        ).counts['structureOnlyFailurePages'] ==
        1,
    'recognition correct but order wrong',
  );
  b[1]['contentFingerprint'] = 'wrong';
  rejects(() => evaluate(t, a, b), 'fingerprint');
  b[1]['contentFingerprint'] = 'synthetic-1';
  var result = pageMetrics(t.first, b.first, 'v3');
  check(result.counts['coveredRegions'] == 1, 'sourceRefs alignment');
  b.first['regions'][0]['sourceRefs'] = <String>[];
  check(
    pageMetrics(t.first, b.first, 'v3').counts['coveredRegions'] == 1,
    'IoU fallback',
  );
  b.first['regions'][0]['bounds']['left'] = 100;
  result = pageMetrics(t.first, b.first, 'v3');
  check(
    result.counts['unmatchedPredictionRegions'] == 1 &&
        result.counts['unmatchedTruthRegions'] == 1,
    'unaligned',
  );
  final mergedTruth = truth('m')
    ..['regions'] = [
      region('a', '甲', ['a']),
      region('b', '乙', ['b'], left: 20),
    ];
  final merged = prediction('m', 'v3')
    ..['regions'] = [
      region('p', '甲\n乙', ['a', 'b'], truth: false),
    ];
  check(
    pageMetrics(
          mergedTruth,
          merged,
          'v3',
        ).counts['ambiguousPredictionRegions'] ==
        1,
    'tie not guessed',
  );
  mergedTruth['explicitAlignment'] = {
    'v3': {
      'p': ['a', 'b'],
    },
  };
  result = pageMetrics(mergedTruth, merged, 'v3');
  check(
    result.counts['coveredRegions'] == 2 &&
        result.counts['legibleChars'] == 2 &&
        result.counts['legibleEdits'] == 0,
    'merged text counted once',
  );
  merged['regions'] = [
    region('p1', '甲', ['s'], truth: false),
    region('p2', '1', ['s'], truth: false, left: 5)..['converted'] = false,
  ];
  check(
    pageMetrics(t.first, merged, 'v3').counts['coveredRegions'] == 0,
    'partial split not fully converted',
  );
  merged['regions'][1]['converted'] = true;
  check(
    pageMetrics(t.first, merged, 'v3').counts['legibleEdits'] == 0,
    'region split does not create artificial whitespace errors',
  );
  final numericTruth = truth('n')
    ..['referenceText'] = '甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲1'
    ..['regions'] = [
      region('e', '甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲1', ['s']),
    ];
  final numeric = prediction('n', 'v3')
    ..['recognizedText'] = '甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲2'
    ..['regions'] = [
      region('p', '甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲甲2', ['s'], truth: false),
    ];
  result = pageMetrics(numericTruth, numeric, 'v3');
  check(
    result.counts['digitMismatchPages'] == 1 &&
        result.counts['wrongConvertedRegions'] == 1 &&
        result.counts['severeConvertedRegions'] == 0,
    'small digit error still wrong conversion',
  );
  stdout.writeln(
    'self-test: $checks checks passed (synthetic only; no quality claim)',
  );
}
