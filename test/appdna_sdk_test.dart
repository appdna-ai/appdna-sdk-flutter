import 'package:flutter_test/flutter_test.dart';
import 'package:appdna_sdk/appdna_sdk.dart';

void main() {
  group('AppDNA SDK smoke tests', () {
    test('AppDNAEnvironment enum has expected values', () {
      expect(AppDNAEnvironment.values.length, 2);
      expect(AppDNAEnvironment.production, isNotNull);
      expect(AppDNAEnvironment.staging, isNotNull);
    });

    test('OnboardingContext can be created and serialized', () {
      const ctx = OnboardingContext(
        source: 'test',
        campaign: 'c1',
      );
      final map = ctx.toMap();
      expect(map['source'], 'test');
      expect(map['campaign'], 'c1');
    });

    test('OnboardingContext with no fields produces empty map', () {
      const ctx = OnboardingContext();
      final map = ctx.toMap();
      expect(map, isEmpty);
    });

    test('PaywallContext can be created and serialized', () {
      final ctx = PaywallContext(placement: 'settings');
      final map = ctx.toMap();
      expect(map['placement'], 'settings');
    });

    test('WebEntitlement can be deserialized from map', () {
      final ent = WebEntitlement.fromMap({
        'isActive': true,
        'status': 'active',
        'planName': 'Pro',
        'priceId': 'price_123',
        'interval': 'month',
      });
      expect(ent.isActive, true);
      expect(ent.status, 'active');
      expect(ent.planName, 'Pro');
    });

    test('DeferredDeepLink can be deserialized from map', () {
      final link = DeferredDeepLink.fromMap({
        'screen': 'promo',
        'params': <String, dynamic>{'code': 'spring'},
        'visitorId': 'v123',
      });
      expect(link.screen, 'promo');
      expect(link.visitorId, 'v123');
      expect(link.params['code'], 'spring');
    });

    test('SurveyResult can be deserialized from map', () {
      final result = SurveyResult.fromMap({
        'surveyId': 's1',
        'completed': true,
        'questionsAnswered': 3,
      });
      expect(result.surveyId, 's1');
      expect(result.completed, true);
      expect(result.questionsAnswered, 3);
    });

    test('Module namespace accessors are available', () {
      // Verify the static module namespace getters exist and return non-null.
      // These are thin wrappers around MethodChannel so we just check references.
      expect(AppDNA.push, isNotNull);
      expect(AppDNA.onboarding, isNotNull);
      expect(AppDNA.paywall, isNotNull);
      expect(AppDNA.remoteConfig, isNotNull);
      expect(AppDNA.features, isNotNull);
      expect(AppDNA.experiments, isNotNull);
      expect(AppDNA.inAppMessages, isNotNull);
      expect(AppDNA.surveys, isNotNull);
      expect(AppDNA.deepLinks, isNotNull);
      expect(AppDNA.billing, isNotNull);
    });
  });
}
