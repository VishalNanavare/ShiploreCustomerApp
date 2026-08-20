// Unit tests for pure helpers. Widget/integration tests that need the network
// layer are added alongside their features.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiplore/core/utils/validators.dart';
import 'package:shiplore/core/utils/formatx.dart';

void main() {
  group('Validators', () {
    test('identifier accepts email and phone, rejects junk', () {
      expect(Validators.identifier('a@b.com'), isNull);
      expect(Validators.identifier('+919811100201'), isNull);
      expect(Validators.identifier('nope'), isNotNull);
      expect(Validators.identifier(''), isNotNull);
    });

    test('pincode must be 6 digits', () {
      expect(Validators.pincode('400076'), isNull);
      expect(Validators.pincode('123'), isNotNull);
    });
  });

  group('Formatx', () {
    test('parses string numerics from the API', () {
      expect(Formatx.toDouble('720.0000'), 720.0);
      expect(Formatx.toInt('3'), 3);
      expect(Formatx.toDouble(null, 5), 5);
    });
  });
}
