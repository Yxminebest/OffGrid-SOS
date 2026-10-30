import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/mesh_attestation.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';

// Test issuer is injected only into in-memory services. Production uses the
// immutable bundled Supabase public key and never imports this test module.
final _issuer = Ed25519().newKeyPair();
Future<MeshAttestationClaims?> verifyTestAttestation(
  Object? proof,
  Map<String, dynamic> cert,
) async {
  final key = await _issuer;
  return MeshAttestation.verify(
    proof,
    cert,
    trustedKeys: {
      'test-issuer': base64Encode((await key.extractPublicKey()).bytes),
    },
  );
}

Future<Map<String, dynamic>> issueTestProof(
  Map<String, dynamic> cert, {
  String role = 'user',
  int? issuedAt,
  int lifetimeSeconds = 86400,
}) async {
  final now = issuedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final payload = utf8.encode(
    jsonEncode({
      'v': 1,
      'iss': MeshAttestation.issuer,
      'sub': cert['userId'],
      'device': cert['device'],
      'ed': cert['ed'],
      'x': cert['x'],
      'role': role,
      'iat': now,
      'exp': now + lifetimeSeconds,
    }),
  );
  return {
    'keyId': 'test-issuer',
    'payload': base64Encode(payload),
    'signature': base64Encode(
      (await Ed25519().sign(payload, keyPair: await _issuer)).bytes,
    ),
  };
}

Future<void> grantTestAttestation(NearbyMeshService mesh, AppUser user) async {
  final cert = await mesh.crypto.certificate(
    mesh.deviceId,
    user.fullName,
    user.id,
  );
  final installed = await mesh.installAttestation(
    await issueTestProof(cert, role: user.role.name),
  );
  if (!installed) throw StateError('Fixture must use injected test verifier');
}
