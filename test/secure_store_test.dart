import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_app/util/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrate moves a legacy token into the keychain and deletes it', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'api_token': 'legacy-tok'});
    final prefs = await SharedPreferences.getInstance();

    final store = SecureStore();
    await store.migrate(prefs);

    expect(await store.readToken(), 'legacy-tok');
    expect(prefs.getString('api_token'), isNull);
  });

  test('migrate never clobbers an existing keychain token', () async {
    FlutterSecureStorage.setMockInitialValues({'api_token': 'keychain-tok'});
    SharedPreferences.setMockInitialValues({'api_token': 'stale-legacy'});
    final prefs = await SharedPreferences.getInstance();

    final store = SecureStore();
    await store.migrate(prefs);

    expect(await store.readToken(), 'keychain-tok');
    expect(prefs.getString('api_token'), isNull);
  });

  test('write/read/delete round trip', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureStore();
    await store.writeToken('t1');
    expect(await store.readToken(), 't1');
    await store.deleteToken();
    expect(await store.readToken(), isNull);
  });
}
