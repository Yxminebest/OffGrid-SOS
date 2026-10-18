import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../data/repositories/message_repository.dart';
import 'nearby_mesh_service.dart';
import 'sync_service.dart';

/// Remembers the destination before opening Android's camera Activity.
/// Lost results are recovered for that same owner, never another signed-in user.
class ChatCameraService {
  ChatCameraService({this.pickPhoto, this.lostFiles, this.savePhoto});
  final Future<XFile?> Function(ImageSource source)? pickPhoto;
  final Future<List<XFile>?> Function()? lostFiles;
  final Future<void> Function(
    AppUser me,
    XFile image,
    Map<String, dynamic> destination,
  )?
  savePhoto;
  static final instance = ChatCameraService();
  static const pendingKey = 'chat_camera_pending_v1';
  final _picker = ImagePicker();
  bool _working = false;

  Future<void> capture(
    AppUser me, {
    String? peerId,
    String? peerName,
    String? caseId,
    String? conversationId,
  }) async {
    if (_working) return;
    _working = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      if (prefs.containsKey(pendingKey)) {
        throw StateError(
          'มีรูปจากกล้องค้างอยู่ กรุณากลับหน้าหลักเพื่อกู้คืนก่อน',
        );
      }
      final destination = <String, dynamic>{
        'owner': me.id,
        'messageId': const Uuid().v4(),
        'peerId': ?peerId,
        'peerName': ?peerName,
        'caseId': ?caseId,
        'conversationId': ?conversationId,
      };
      await prefs.setString(pendingKey, jsonEncode(destination));
      final image = pickPhoto != null
          ? await pickPhoto!(ImageSource.camera)
          : await _picker.pickImage(
              source: ImageSource.camera,
              maxWidth: 1920,
              maxHeight: 1920,
              imageQuality: 85,
            );
      if (image == null) {
        await prefs.remove(pendingKey);
        return;
      }
      destination['path'] = image.path;
      destination['name'] = image.name;
      await prefs.setString(pendingKey, jsonEncode(destination));
      await (savePhoto ?? _save)(me, image, destination);
      await prefs.remove(pendingKey);
    } catch (_) {
      final raw = prefs.getString(pendingKey);
      if (raw != null && (jsonDecode(raw) as Map)['path'] == null) {
        // Permission/camera launch failure has no file to recover. Allow retry.
        await prefs.remove(pendingKey);
      }
      rethrow;
    } finally {
      _working = false;
    }
  }

  Future<bool> recoverFor(AppUser me) async {
    if (_working || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    _working = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingKey);
      if (raw == null) return false;
      final destination = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (destination['owner'] != me.id) return false;
      destination['messageId'] ??= const Uuid().v4();
      await prefs.setString(pendingKey, jsonEncode(destination));
      if (destination['path'] == null) {
        final files = lostFiles != null
            ? await lostFiles!()
            : (await _picker.retrieveLostData()).files;
        final image = files?.firstOrNull;
        if (image == null) {
          await prefs.remove(pendingKey);
          return false;
        }
        destination['path'] = image.path;
        destination['name'] = image.name;
        await prefs.setString(pendingKey, jsonEncode(destination));
      }
      if (destination['owner'] != me.id) return false;
      await (savePhoto ?? _save)(
        me,
        XFile(destination['path'], name: destination['name']),
        destination,
      );
      await prefs.remove(pendingKey);
      return true;
    } finally {
      _working = false;
    }
  }

  Future<void> discardFor(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(pendingKey);
    if (raw != null && (jsonDecode(raw) as Map)['owner'] == owner) {
      await prefs.remove(pendingKey);
    }
  }

  Future<void> _save(
    AppUser me,
    XFile image,
    Map<String, dynamic> destination,
  ) async {
    final mesh = NearbyMeshService.instance;
    if (mesh.ownerId != me.id || destination['owner'] != me.id) {
      throw StateError('บัญชีเปลี่ยนแล้ว รูปเก็บไว้รอกู้คืนในบัญชีเดิม');
    }
    final peer = destination['peerId'];
    if (peer is String) {
      await mesh.sendAttachment(
        messageId: destination['messageId'],
        target: peer,
        path: image.path,
        name: image.name,
        type: 'image',
        peerName: destination['peerName'],
        caseId: destination['caseId'],
      );
    } else {
      final conversation = destination['conversationId'];
      if (conversation is! String) throw StateError('ไม่พบห้องสนทนา');
      final length = await image.length();
      if (length <= 0 || length > 25 * 1024 * 1024) {
        throw StateError('รูปต้องมีขนาดไม่เกิน 25 MB');
      }
      await MessageRepository().create(
        messageId: destination['messageId'],
        user: me,
        conversationId: conversation,
        type: 'image',
        content: '📷 รูปถ่าย',
        mediaName: image.name,
        mediaMime: 'image/jpeg',
        mediaBytes: await image.readAsBytes(),
      );
      unawaited(SyncService.instance.syncNow().catchError((Object _) {}));
    }
  }
}
