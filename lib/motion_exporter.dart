/// Flutter widget motion capture, deterministic rendering, and export APIs.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        ErrorDescription,
        FlutterError,
        FlutterErrorDetails,
        VoidCallback,
        compute,
        kReleaseMode;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart'
    show
        Alignment,
        AnimatedBuilder,
        BorderRadius,
        BoxDecoration,
        BoxShadow,
        BoxShape,
        BuildContext,
        Center,
        CustomPaint,
        CustomPainter,
        DecoratedBox,
        Directionality,
        EdgeInsets,
        FontWeight,
        GestureDetector,
        GlobalKey,
        HitTestBehavior,
        Key,
        MainAxisSize,
        Offset,
        Padding,
        Positioned,
        RepaintBoundary,
        Row,
        Semantics,
        SingleTickerProviderStateMixin,
        Size,
        SizedBox,
        Stack,
        StackFit,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextDecoration,
        TextDirection,
        TextStyle,
        Widget,
        WidgetsBinding;
import 'package:image/image.dart' as img;

part 'src/motion_clip_encoder.dart';
part 'src/motion_clip_golden.dart';
part 'src/motion_export_engine.dart';
part 'src/motion_export_inspection.dart';
part 'src/motion_capture_quality_policy.dart';
part 'src/motion_capture_estimate.dart';
part 'src/motion_recorder.dart';
part 'src/motion_exporter_overlay.dart';
part 'src/motion_canvas_recorder.dart';
part 'src/motion_loop_signal.dart';
part 'src/apng_animation_encoder.dart';
part 'src/webp_animation_encoder.dart';
part 'src/webp_animation_stream_encoder.dart';
part 'src/webp_frame.dart';
part 'src/motion_recorder_controller.dart';
part 'src/motion_recorder_options.dart';
part 'src/motion_recorder_widget.dart';
