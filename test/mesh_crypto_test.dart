import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/mesh_crypto.dart';

void main() {
  test(
    'reused shared key keeps unique nonces and account changes invalidate it',
    () async {
      MeshCrypto make() {
        final store = <String, String>{};
        return MeshCrypto(
          read: (k) async => store[k],
          write: (k, v) async {
            store[k] = v;
          },
        );
      }

      final a = make(), b = make();
      await a.initialize('a');
      await b.initialize('b');
      final aCert = await a.certificate('a-device', 'A', null);
      final bCert = await b.certificate('b-device', 'B', null);
      final first = await a.seal(bCert, {'value': 1}, 'binding');
      final second = await a.seal(bCert, {'value': 2}, 'binding');
      expect(first['nonce'], isNot(second['nonce']));
      expect((await b.open(aCert, first, 'binding'))['value'], 1);
      expect((await b.open(aCert, second, 'binding'))['value'], 2);
      await a.initialize('another-account');
      final newCert = await a.certificate('a-device', 'Other', null);
      final third = await a.seal(bCert, {'value': 3}, 'binding');
      expect((await b.open(newCert, third, 'binding'))['value'], 3);
      await expectLater(b.open(aCert, third, 'binding'), throwsA(anything));
    },
  );
  test(
    'keys persist, TOFU rejects a replacement key, ciphertext binds recipient',
    () async {
      final aStore = <String, String>{}, bStore = <String, String>{};
      MeshCrypto instance(Map<String, String> store) => MeshCrypto(
        read: (key) async => store[key],
        write: (key, value) async {
          store[key] = value;
        },
      );
      final a = instance(aStore), b = instance(bStore);
      await a.initialize('owner-a');
      await b.initialize('owner-b');
      final aCert = await a.certificate('device-a', 'A', null);
      final bCert = await b.certificate('device-b', 'B', null);
      expect(await a.accept(bCert), true);
      final box = await a.seal(bCert, {'text': 'private'}, 'a|b|packet');
      expect(await b.open(aCert, box, 'a|b|packet'), {'text': 'private'});
      await expectLater(b.open(aCert, box, 'a|c|packet'), throwsA(anything));
      final reopened = instance(aStore);
      await reopened.initialize('owner-a');
      final reopenedCert = await reopened.certificate('device-a', 'A', null);
      expect(reopenedCert['x'], aCert['x']);
      expect(reopenedCert['ed'], aCert['ed']);
      final replacement = instance({});
      await replacement.initialize('other-owner');
      expect(
        await a.accept(
          await replacement.certificate('device-b', 'Imposter', null),
        ),
        false,
      );
      expect(await b.accept({...aCert, 'name': 'modified'}), false);
    },
  );
}
