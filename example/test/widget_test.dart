import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:motion_exporter_example/main.dart';

void main() {
  testWidgets('renders recorder demo controls', (tester) async {
    await tester.pumpWidget(const MotionExporterExampleApp());

    expect(find.text('Motion Exporter'), findsOneWidget);
    expect(find.text('Record loop'), findsOneWidget);
    expect(find.text('Render 120 fps'), findsOneWidget);
    expect(find.text('One loop'), findsOneWidget);
    expect(find.text('0 frames'), findsOneWidget);
  });

  testWidgets('renders deterministic 120 fps clip at requested frame count', (
    tester,
  ) async {
    final clip = await tester.runAsync(
      () => renderTransparentDemoClip(
        framesPerSecond: 120,
        duration: const Duration(milliseconds: 101),
        size: 16,
      ),
    );

    expect(clip!.frameCount, 13);
    expect(clip.width, 16);
    expect(clip.height, 16);
    expect(clip.duration, const Duration(milliseconds: 101));
  });

  testWidgets('records and shows export details', (tester) async {
    await tester.pumpWidget(const MotionExporterExampleApp());

    const recordButton = Key('motion_exporter_example_record_button');

    await tester.tap(find.byKey(recordButton));
    await tester.pump();
    expect(find.text('Waiting for loop'), findsOneWidget);

    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('motion_exporter_example_playback'))
          .evaluate()
          .isNotEmpty,
      maxPumps: 500,
    );

    expect(find.text('WebP'), findsWidgets);
    expect(find.text('1 loop'), findsWidgets);
    expect(find.textContaining('KB'), findsWidgets);
    expect(find.textContaining('ms'), findsWidgets);
    expect(find.textContaining('frames'), findsWidgets);
    expect(find.textContaining('encoded frames'), findsWidgets);
    expect(find.text('2.00 s'), findsWidgets);
    expect(find.text('live'), findsWidgets);
    expect(find.textContaining('live_loop_'), findsWidgets);
    expect(find.textContaining('.webp'), findsWidgets);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 50,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for example widget condition.');
}
