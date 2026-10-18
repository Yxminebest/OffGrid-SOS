import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/chat_camera_service.dart';

const me = AppUser(
  id: 'camera-user',
  firstName: 'A',
  lastName: 'Test',
  isMember: false,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'camera source and original Nearby destination are retained until saved',
    () async {
      Map<String, dynamic>? saved;
      final camera = ChatCameraService(
        pickPhoto: (source) async {
          expect(source, ImageSource.camera);
          final prefs = await SharedPreferences.getInstance();
          expect(
            jsonDecode(
              prefs.getString(ChatCameraService.pendingKey)!,
            )['peerId'],
            'peer-1',
          );
          return XFile('/camera/photo.jpg');
        },
        savePhoto: (user, file, destination) async {
          saved = destination;
        },
      );
      await camera.capture(
        me,
        peerId: 'peer-1',
        peerName: 'เพื่อน',
        caseId: 'case-1',
      );
      expect(saved?['caseId'], 'case-1');
      expect(saved?['path'], '/camera/photo.jpg');
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          ChatCameraService.pendingKey,
        ),
        isFalse,
      );
    },
  );

  test('canceling camera creates no message or pending recovery', () async {
    final camera = ChatCameraService(
      pickPhoto: (_) async => null,
      savePhoto: (_, _, _) async => fail('cancel must not send'),
    );
    await camera.capture(me, peerId: 'peer-1');
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        ChatCameraService.pendingKey,
      ),
      isFalse,
    );
  });

  test(
    'camera permission failure clears the empty draft so capture can retry',
    () async {
      final camera = ChatCameraService(
        pickPhoto: (_) async => throw StateError('camera denied'),
      );
      await expectLater(camera.capture(me, peerId: 'peer-1'), throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          ChatCameraService.pendingKey,
        ),
        isFalse,
      );
    },
  );

  test(
    'lost Android camera result returns only to its original account and cloud room',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ChatCameraService.pendingKey,
        jsonEncode({'owner': me.id, 'conversationId': 'cloud-room'}),
      );
      var saved = 0;
      final camera = ChatCameraService(
        lostFiles: () async => [XFile('/recovered/photo.jpg')],
        savePhoto: (user, file, destination) async {
          saved++;
          expect(destination['conversationId'], 'cloud-room');
        },
      );
      const other = AppUser(
        id: 'other',
        firstName: 'B',
        lastName: 'Test',
        isMember: false,
      );
      expect(await camera.recoverFor(other), isFalse);
      expect(saved, 0);
      expect(prefs.containsKey(ChatCameraService.pendingKey), isTrue);
      expect(await camera.recoverFor(me), isTrue);
      expect(saved, 1);
      expect(prefs.containsKey(ChatCameraService.pendingKey), isFalse);
    },
  );
}
