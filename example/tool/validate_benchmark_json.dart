import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    _fail('Usage: dart run tool/validate_benchmark_json.dart <benchmark.json>');
  }

  final root = jsonDecode(File(args.single).readAsStringSync());
  if (root is! Map<String, Object?> || root['schemaVersion'] != 3) {
    _fail('Expected benchmark schemaVersion 3.');
  }

  final environment = _map(root, 'environment');
  _nonEmptyString(environment, 'dartVersion');
  _nonEmptyString(environment, 'operatingSystem');
  _nonEmptyString(environment, 'operatingSystemVersion');
  _positiveInt(environment, 'numberOfProcessors');

  final scene = _map(root, 'scene');
  final frames = _positiveInt(scene, 'frames');
  _positiveInt(scene, 'width');
  _positiveInt(scene, 'height');
  _positiveInt(scene, 'durationMicros');
  _positiveInt(scene, 'rawBytes');
  _positiveNum(scene, 'rawMebibytes');

  final golden = _map(root, 'golden');
  if (golden['format'] != '.motion') {
    _fail('Expected .motion golden benchmark format.');
  }
  if (_positiveInt(golden, 'frames') != frames) {
    _fail('Frame count mismatch for .motion golden.');
  }
  final goldenBytes = _positiveInt(golden, 'bytes');
  final goldenKibibytes = _positiveNum(golden, 'kibibytes');
  if ((goldenBytes / 1024 - goldenKibibytes).abs() > 0.001) {
    _fail('KiB mismatch for .motion golden.');
  }
  _nonNegativeInt(golden, 'encodeMicros');
  _nonNegativeInt(golden, 'decodeMicros');
  final goldenCompareMicros = _nonNegativeInt(golden, 'compareMicros');

  final results = root['results'];
  if (results is! List || results.length != 5) {
    _fail('Expected 5 benchmark result rows.');
  }

  final rows = <String, Map<String, Object?>>{};
  for (final value in results) {
    if (value is! Map<String, Object?>) {
      _fail('Benchmark result row must be an object.');
    }
    final name = value['name'];
    if (name is! String || name.isEmpty) {
      _fail('Benchmark result row must have a name.');
    }
    if (rows.containsKey(name)) {
      _fail('Duplicate benchmark row: $name.');
    }
    final format = value['format'];
    if (format != 'WebP' && format != 'APNG') {
      _fail('Unexpected format for $name: $format.');
    }
    if (_positiveInt(value, 'frames') != frames) {
      _fail('Frame count mismatch for $name.');
    }
    final bytes = _positiveInt(value, 'bytes');
    final kibibytes = _positiveNum(value, 'kibibytes');
    if ((bytes / 1024 - kibibytes).abs() > 0.001) {
      _fail('KiB mismatch for $name.');
    }
    final encodeMicros = _positiveInt(value, 'encodeMicros');
    if (_positiveInt(value, 'totalMicros') < encodeMicros) {
      _fail('Total time is less than encode time for $name.');
    }
    rows[name] = value;
  }

  _requireRows(rows, <String>[
    'WebP default changed rect',
    'WebP transparent trim',
    'WebP full canvas',
    'APNG transparent trim',
    'APNG full canvas',
  ]);
  _expectAtMost(
    rows,
    smaller: 'WebP default changed rect',
    larger: 'WebP full canvas',
    metric: 'bytes',
  );
  _expectAtMost(
    rows,
    smaller: 'WebP default changed rect',
    larger: 'WebP full canvas',
    metric: 'encodeMicros',
  );
  _expectAtMost(
    rows,
    smaller: 'APNG transparent trim',
    larger: 'APNG full canvas',
    metric: 'bytes',
  );
  _expectAtMost(
    rows,
    smaller: 'APNG transparent trim',
    larger: 'APNG full canvas',
    metric: 'encodeMicros',
  );
  _expectValueAtMost(
    value: goldenCompareMicros,
    valueName: '.motion compareMicros',
    max: _positiveInt(rows['APNG transparent trim']!, 'encodeMicros'),
    maxName: 'APNG transparent trim encodeMicros',
  );
}

Map<String, Object?> _map(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  _fail('Expected $key to be an object.');
}

int _positiveInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is int && value > 0) {
    return value;
  }
  _fail('Expected positive integer $key.');
}

int _nonNegativeInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is int && value >= 0) {
    return value;
  }
  _fail('Expected non-negative integer $key.');
}

num _positiveNum(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is num && value > 0) {
    return value;
  }
  _fail('Expected positive number $key.');
}

String _nonEmptyString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  _fail('Expected non-empty string $key.');
}

void _requireRows(Map<String, Map<String, Object?>> rows, List<String> names) {
  for (final name in names) {
    if (!rows.containsKey(name)) {
      _fail('Missing benchmark row: $name.');
    }
  }
}

void _expectAtMost(
  Map<String, Map<String, Object?>> rows, {
  required String smaller,
  required String larger,
  required String metric,
}) {
  if (_positiveInt(rows[smaller]!, metric) >
      _positiveInt(rows[larger]!, metric)) {
    _fail('$smaller must not exceed $larger by $metric.');
  }
}

void _expectValueAtMost({
  required int value,
  required String valueName,
  required int max,
  required String maxName,
}) {
  if (value > max) {
    _fail('$valueName must not exceed $maxName.');
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
