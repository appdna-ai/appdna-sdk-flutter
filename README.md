# AppDNA SDK for Flutter

The official Flutter SDK for [AppDNA](https://appdna.ai) — the growth console for subscription apps.

> ⚠️ **Proprietary software.** A Commercial Agreement with AppDNA AI, Inc. is required to use this SDK. See [LICENSE](./LICENSE) and [NOTICE.md](./NOTICE.md).
>
> **Migrating from MIT-licensed v1.0.0 or earlier?** See [DEPRECATION_NOTICE.md](./DEPRECATION_NOTICE.md). MIT versions stop receiving server support after **15 May 2026**.

## What it does

AppDNA gives you a single drop-in SDK for the growth surfaces every subscription app needs, on both iOS and Android from one Dart codebase:

- **Analytics & events** — track user behavior with batched, offline-resilient delivery.
- **Experiments & feature flags** — server-driven A/B tests with deterministic variant assignment.
- **Paywalls** — render console-designed paywall layouts with native StoreKit 2 / Google Play Billing.
- **Onboarding flows** — multi-step onboarding with form inputs, async hooks, conditional branching, and rich media.
- **Surveys & feedback** — NPS, CSAT, free text, multi-choice with scheduling and frequency caps.
- **In-app messages** — modal, banner, fullscreen messages with audience targeting.
- **Push notifications** — rich content, action buttons, deep links, and delivery analytics.
- **Web entitlements & deep links** — server-validated entitlements and deferred deep linking.

## Requirements

- Flutter 3.10+
- Dart 3.0+
- iOS 16.0+ (when targeting iOS)
- Android API 24+ (when targeting Android)

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  appdna_sdk:
    git:
      url: https://github.com/appdna-ai/appdna-sdk-flutter.git
      ref: v1.0.2
```

Then run:

```bash
flutter pub get
```

For iOS, also run:

```bash
cd ios && pod install
```

## Quick start

```dart
import 'package:appdna_sdk/appdna_sdk.dart';

await AppDNA.configure('YOUR_API_KEY');
```

Track an event:

```dart
await AppDNA.track('subscription_viewed', {'plan_id': 'premium_monthly'});
```

Identify a user (after sign-in):

```dart
await AppDNA.identify('user-123', {'plan': 'premium'});
```

Present a paywall:

```dart
final result = await AppDNA.presentPaywall(id: 'default');
switch (result) {
  case PaywallResult.purchased:
    print('Purchased');
  case PaywallResult.dismissed:
    print('Dismissed');
  case PaywallResult.failed:
    print('Failed');
}
```

## Documentation

Full integration guide, configuration reference, and API docs at **[docs.appdna.ai/sdks/flutter](https://docs.appdna.ai/sdks/flutter/installation)**.

## Support

- Technical questions: [support@appdna.ai](mailto:support@appdna.ai)
- Sales / commercial: [sales@appdna.ai](mailto:sales@appdna.ai)
- Licensing: [legal@appdna.ai](mailto:legal@appdna.ai)

## License

⚠️ **The AppDNA SDK is proprietary software, not open source.** This repository is publicly visible for marketing, evaluation, and reference purposes only.

**You may NOT** download, install, run, modify, or use the SDK without a Commercial Agreement with AppDNA AI, Inc. See [LICENSE](./LICENSE) and [NOTICE.md](./NOTICE.md) for the full terms.

**You MAY** view the source on GitHub and read the documentation at <https://docs.appdna.ai> for evaluation purposes.

To use the SDK in your application, sign up at <https://appdna.ai> (self-serve) or contact <sales@appdna.ai> (enterprise).

**Existing customers**: your Terms of Service or Statement of Work governs your use of the SDK.

**Versions before v1.0.1** were distributed under the MIT License — see [DEPRECATION_NOTICE.md](./DEPRECATION_NOTICE.md) for the migration timeline (deadline: **15 May 2026**).

---

© 2026 AppDNA AI, Inc. All rights reserved. "AppDNA" and the AppDNA logo are trademarks of AppDNA AI, Inc.
