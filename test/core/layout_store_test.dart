import 'package:ensi/core/layout_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offsets persist across a reload', () async {
    final a = LayoutStore();
    await a.load();
    await a.set('dev1', 1920, 0);
    await a.set('dev2', -1080, 200);

    final b = LayoutStore();
    await b.load();
    expect(b.offsetFor('dev1'), (x: 1920.0, y: 0.0));
    expect(b.offsetFor('dev2'), (x: -1080.0, y: 200.0));
    expect(b.offsetFor('missing'), isNull);
  });
}
