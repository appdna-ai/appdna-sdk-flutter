# AppDNA SDK for Flutter

The official Flutter SDK for [AppDNA](https://appdna.ai) — the growth console for subscription apps.

## Installation

Add to your pubspec.yaml:

```yaml
dependencies:
  appdna_sdk:
    git:
      url: https://github.com/appdna-ai/appdna-sdk-flutter.git
      ref: v1.0.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:appdna_sdk/appdna_sdk.dart';

await AppDNA.configure('YOUR_API_KEY');
```

## Documentation

Full documentation at [docs.appdna.ai](https://docs.appdna.ai/sdks/flutter/installation)

## License

MIT — see [LICENSE](LICENSE) for details.
