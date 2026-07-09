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
      const ctx = PaywallContext(placement: 'settings');
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

    test('SurveyResult parses the payload the platform channel actually sends', () {
      // The channel sends `responses`, not `answers`. The old test fed the model
      // its own keys and so never noticed that `answers` was always null.
      // ignore: deprecated_member_use_from_same_package
      final result = SurveyResult.fromMap({
        'surveyId': 's1',
        'responses': [
          {'questionId': 'q1', 'answer': 'yes'},
          {'questionId': 'q2', 'answer': 4},
        ],
      });
      expect(result.surveyId, 's1');
      expect(result.answers, isNotNull);
      expect(result.answers!.length, 2);
      expect(result.answers![0].questionId, 'q1');
      expect(result.answers![0].answer, 'yes');
      expect(result.answers![1].answer, 4);
      // Derived, since the wire carries neither field.
      expect(result.completed, true);
      expect(result.questionsAnswered, 2);
    });

    test('SurveyResult still accepts the legacy `answers` key', () {
      // ignore: deprecated_member_use_from_same_package
      final result = SurveyResult.fromMap({
        'surveyId': 's2',
        'answers': [
          {'questionId': 'q1', 'answer': 'ok'},
        ],
      });
      expect(result.answers!.single.questionId, 'q1');
      expect(result.questionsAnswered, 1);
    });

    test('SurveyResult with no responses is not a completion', () {
      // ignore: deprecated_member_use_from_same_package
      final result = SurveyResult.fromMap({'surveyId': 's3'});
      expect(result.completed, false);
      expect(result.questionsAnswered, 0);
      expect(result.answers, isNull);
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
