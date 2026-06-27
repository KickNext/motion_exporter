import 'dart:io';

import 'package:motion_exporter/motion_exporter.dart';

Future<String> writeRecording(
  MotionExportResult result, {
  required String basename,
}) async {
  final dir = Directory.systemTemp.createTempSync('motion_exporter_');
  final file = File(
    '${dir.path}${Platform.pathSeparator}${result.fileName(basename: basename)}',
  );
  await file.writeAsBytes(result.bytes, flush: true);
  return file.path;
}
