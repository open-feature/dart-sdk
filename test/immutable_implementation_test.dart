import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'independent package archives share identical immutable value semantics',
    () {
      String source(String package) => File(
        'packages/openfeature_dart_${package}_sdk/lib/src/immutable.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(source('server'), source('client'));
    },
  );
}
