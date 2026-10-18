import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Signed discovery identities plus authenticated end-to-end routed payloads.
/// Peer keys use trust on first contact; keep pins across reconnects/restarts.
class MeshCrypto {
  MeshCrypto({required this.read, required this.write});
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  late SimpleKeyPair _exchange, _signing;
  final _dh = X25519();
  final _ed = Ed25519();
  final _aes = AesGcm.with256bits();
  String _owner = '';
  Future<void> initialize(String owner) async {
    _owner = owner;
    final key = 'mesh_keys_v1_$owner';
    final raw = await read(key);
    if (raw == null) {
      _exchange = await _dh.newKeyPair();
      _signing = await _ed.newKeyPair();
      await write(
        key,
        jsonEncode({
          'x': base64Encode(await _exchange.extractPrivateKeyBytes()),
          'ed': base64Encode(await _signing.extractPrivateKeyBytes()),
        }),
      );
    } else {
      final saved = jsonDecode(raw) as Map;
      _exchange = await _dh.newKeyPairFromSeed(base64Decode(saved['x']));
      _signing = await _ed.newKeyPairFromSeed(base64Decode(saved['ed']));
    }
  }

  List<int> _canonical(Map value) => utf8.encode(
    jsonEncode(
      Map.fromEntries(
        value.entries.where((e) => e.key != 'signature').toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString())),
      ),
    ),
  );
  Future<Map<String, dynamic>> certificate(
    String id,
    String name,
    String? userId,
  ) async {
    final value = <String, dynamic>{
      'device': id,
      'name': name,
      'userId': userId,
      'x': base64Encode((await _exchange.extractPublicKey()).bytes),
      'ed': base64Encode((await _signing.extractPublicKey()).bytes),
    };
    value['signature'] = base64Encode(
      (await _ed.sign(_canonical(value), keyPair: _signing)).bytes,
    );
    return value;
  }

  Future<bool> accept(Map<String, dynamic> cert) async {
    try {
      if (cert['device'] is! String ||
          (cert['device'] as String).isEmpty ||
          (cert['device'] as String).length > 128 ||
          cert['name'] is! String ||
          (cert['name'] as String).length > 200) {
        return false;
      }
      if (cert['userId'] != null &&
          (cert['userId'] is! String ||
              (cert['userId'] as String).length > 128)) {
        return false;
      }
      final ed = base64Decode(cert['ed']);
      if (ed.length != 32 || base64Decode(cert['x']).length != 32) return false;
      if (!await _ed.verify(
        _canonical(cert),
        signature: Signature(
          base64Decode(cert['signature']),
          publicKey: SimplePublicKey(ed, type: KeyPairType.ed25519),
        ),
      )) {
        return false;
      }
      final key = 'mesh_pin_${_owner}_${cert['device']}';
      final pin = '${cert['ed']}:${cert['x']}';
      final old = await read(key);
      if (old != null && old != pin) return false;
      if (old == null) await write(key, pin);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SecretKey> _shared(Map cert) => _dh.sharedSecretKey(
    keyPair: _exchange,
    remotePublicKey: SimplePublicKey(
      base64Decode(cert['x']),
      type: KeyPairType.x25519,
    ),
  );
  Future<Map<String, dynamic>> seal(
    Map cert,
    Map<String, dynamic> message,
    String binding,
  ) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(message)),
      secretKey: await _shared(cert),
      aad: utf8.encode(binding),
    );
    return {
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<Map<String, dynamic>> open(Map cert, Map box, String binding) async {
    final bytes = await _aes.decrypt(
      SecretBox(
        base64Decode(box['cipher']),
        nonce: base64Decode(box['nonce']),
        mac: Mac(base64Decode(box['mac'])),
      ),
      secretKey: await _shared(cert),
      aad: utf8.encode(binding),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }
}
