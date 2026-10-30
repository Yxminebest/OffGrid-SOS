import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/mesh_attestation.dart';
import 'package:offgrid_sos/services/mesh_crypto.dart';
import 'support/mesh_issuer.dart';

void main() {
  late Map<String, dynamic> cert;
  setUp(() async {
    final storage = <String, String>{};
    final crypto = MeshCrypto(
      read: (key) async => storage[key],
      write: (key, value) async {
        storage[key] = value;
      },
    );
    await crypto.initialize('account');
    cert = await crypto.certificate('device', 'Name', 'account');
  });
  test('signed account and rescue role verify without network', () async {
    final proof = await issueTestProof(cert, role: 'rescuer');
    final claims = await verifyTestAttestation(proof, cert);
    expect(claims!.userId, 'account');
    expect(claims.rescuer, isTrue);
  });
  test('production trust anchor rejects the test issuer', () async {
    expect(
      await MeshAttestation.verify(await issueTestProof(cert), cert),
      isNull,
    );
  });
  test('changing a signed role does not create a rescuer', () async {
    final proof = await issueTestProof(cert);
    final payload =
        jsonDecode(utf8.decode(base64Decode(proof['payload']))) as Map;
    payload['role'] = 'admin';
    proof['payload'] = base64Encode(utf8.encode(jsonEncode(payload)));
    expect(await verifyTestAttestation(proof, cert), isNull);
  });
  test('copying proof to a different device or account fails', () async {
    final proof = await issueTestProof(cert);
    expect(
      await verifyTestAttestation(proof, {...cert, 'device': 'other'}),
      isNull,
    );
    expect(
      await verifyTestAttestation(proof, {...cert, 'userId': 'other'}),
      isNull,
    );
    expect(
      await verifyTestAttestation(proof, {...cert, 'ed': 'other'}),
      isNull,
    );
  });
  test('expired valid signature cannot retain rescue authorization', () async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final proof = await issueTestProof(
      cert,
      role: 'rescuer',
      issuedAt: now - 100,
      lifetimeSeconds: 50,
    );
    expect(await verifyTestAttestation(proof, cert), isNull);
  });
  test('future-issued and excessive lifetime proofs fail closed', () async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(
      await verifyTestAttestation(
        await issueTestProof(cert, issuedAt: now + 1000),
        cert,
      ),
      isNull,
    );
    expect(
      await verifyTestAttestation(
        await issueTestProof(cert, lifetimeSeconds: 31 * 86400),
        cert,
      ),
      isNull,
    );
  });
}
