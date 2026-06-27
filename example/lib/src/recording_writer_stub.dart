import 'package:motion_exporter/motion_exporter.dart';

Future<String> writeRecording(
  MotionExportResult result, {
  required String basename,
}) async {
  return result.fileName(basename: basename);
}
