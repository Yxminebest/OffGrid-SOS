import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class MeshAttestationClaims {
  const MeshAttestationClaims(this.userId, this.role, this.expiresAt);
  final String userId, role;
  final DateTime expiresAt;
  bool get current => DateTime.now().isBefore(expiresAt);
  bool get rescuer => current && (role == 'rescuer' || role == 'admin');
}

/// Trust anchor is bundled with the APK. Never trust a key supplied by a peer
/// or automatically replace this key with a value fetched over the network.
class MeshAttestation {
  static const issuer = 'evfopzvqsngrunopxgvl';
  static const keyId = 'mesh-2026-10';
  static const publicKey = 'O3QMQ4JlLs/CdOy9Gd1WS2u4Row/yxG7kyocdlNmgrE=';

  static Future<MeshAttestationClaims?> verify(
    Object? proof,
    Map<String, dynamic> certificate, {
    DateTime? now,
    Map<String, String> trustedKeys = const {keyId: publicKey},
  }) async {
    try {
      if (proof is! Map ||
          !trustedKeys.containsKey(proof['keyId']) ||
          proof['payload'] is! String ||
          proof['signature'] is! String ||
          (proof['payload'] as String).length > 4096 ||
          (proof['signature'] as String).length > 100) {
        return null;
      }
      final bytes = base64Decode(proof['payload']);
      if (!await Ed25519().verify(
        bytes,
        signature: Signature(
          base64Decode(proof['signature']),
          publicKey: SimplePublicKey(
            base64Decode(trustedKeys[proof['keyId']]!),
            type: KeyPairType.ed25519,
          ),
        ),
      )) {
        return null;
      }
      final p = jsonDecode(utf8.decode(bytes)) as Map;
      if (p['v'] != 1 ||
          p['iss'] != issuer ||
          p['sub'] is! String ||
          p['sub'] != certificate['userId'] ||
          p['device'] != certificate['device'] ||
          p['ed'] != certificate['ed'] ||
          p['x'] != certificate['x'] ||
          !['user', 'rescuer', 'admin'].contains(p['role']) ||
          p['iat'] is! int ||
          p['exp'] is! int) {
        return null;
      }
      final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      if (p['iat'] > seconds + 300 ||
          p['exp'] <= seconds ||
          p['exp'] <= p['iat'] ||
          p['exp'] - p['iat'] > 30 * 86400) {
        return null;
      }
      return MeshAttestationClaims(
        p['sub'],
        p['role'],
        DateTime.fromMillisecondsSinceEpoch(p['exp'] * 1000, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }
}
