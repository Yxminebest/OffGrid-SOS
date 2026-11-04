import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:offgrid_sos/widgets/nearby_media_preview_io.dart';
import 'package:offgrid_sos/services/unified_chat_service.dart';

class FakeVideo extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  bool played = false, paused = false, disposed = false;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int id) => events.stream;
  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setVolume(int id, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<void> play(int id) async {
    played = true;
  }

  @override
  Future<void> pause(int id) async {
    paused = true;
  }

  @override
  Future<void> seekTo(int id, Duration position) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Future<void> dispose(int id) async {
    disposed = true;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

void main() {
  test(
    'delivery labels describe available transport, never remote presence',
    () {
      expect(
        UnifiedChatService.deliveryLabel(nearby: false, cloud: false),
        'ออฟไลน์',
      );
      expect(
        UnifiedChatService.deliveryLabel(nearby: false, cloud: true),
        'ออนไลน์',
      );
      expect(
        UnifiedChatService.deliveryLabel(nearby: true, cloud: false),
        'ออฟไลน์',
      );
      expect(
        UnifiedChatService.deliveryLabel(nearby: true, cloud: true),
        'ออนไลน์',
      );
    },
  );
  testWidgets(
    'portrait local video starts playing, controls fit, pauses in background and disposes',
    (tester) async {
      final previous = VideoPlayerPlatform.instance;
      final video = FakeVideo();
      VideoPlayerPlatform.instance = video;
      addTearDown(() async {
        VideoPlayerPlatform.instance = previous;
        await video.events.close();
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NearbyMediaPreview(
              path: '/sample.mp4',
              type: 'video',
              name: 'sample',
            ),
          ),
        ),
      );
      await tester.tap(find.text('เล่นวิดีโอในเครื่อง'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      video.events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 1),
          size: const Size(1080, 1920),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(video.played, isTrue);
      expect(find.byTooltip('หยุดชั่วคราว'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final control = tester.getRect(find.byTooltip('หยุดชั่วคราว'));
      expect(
        control.bottom,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      video.paused = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(video.paused, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(video.disposed, isTrue);
    },
  );
}
