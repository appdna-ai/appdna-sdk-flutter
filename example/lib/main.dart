import 'package:flutter/material.dart';
import 'package:appdna_sdk/appdna_sdk.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppDNA SDK Example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6366f1), useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'Not configured';
  String? _webEntitlement;
  String? _deepLink;

  @override
  void initState() {
    super.initState();
    _initSdk();
  }

  Future<void> _initSdk() async {
    // 1. Configure SDK
    await AppDNA.configure(apiKey: 'YOUR_API_KEY');
    setState(() => _status = 'Configured');

    // 2. Identify user
    await AppDNA.identify('user_123', traits: {'email': 'demo@example.com'});
    setState(() => _status = 'Identified');

    // 3. Check for deferred deep link (first launch)
    final link = await AppDNA.checkDeferredDeepLink();
    if (link != null) {
      setState(() => _deepLink = '${link.screen} (${link.params})');
    }

    // 4. Listen for web entitlement changes
    AppDNA.onWebEntitlementChanged.listen((entitlement) {
      setState(() {
        _webEntitlement = entitlement != null
            ? '${entitlement.planName} (${entitlement.status})'
            : 'None';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AppDNA SDK Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _infoCard('SDK Status', _status),
          _infoCard('Web Entitlement', _webEntitlement ?? 'Not loaded'),
          _infoCard('Deferred Deep Link', _deepLink ?? 'None'),
          const SizedBox(height: 24),

          // Track Event
          FilledButton.icon(
            onPressed: () => AppDNA.track('button_tapped', properties: {'button': 'demo'}),
            icon: const Icon(Icons.analytics),
            label: const Text('Track Event'),
          ),
          const SizedBox(height: 12),

          // Present Paywall
          FilledButton.icon(
            onPressed: () => AppDNA.presentPaywall('default'),
            icon: const Icon(Icons.shopping_cart),
            label: const Text('Present Paywall'),
          ),
          const SizedBox(height: 12),

          // Present Onboarding
          FilledButton.icon(
            onPressed: () => AppDNA.presentOnboarding('default'),
            icon: const Icon(Icons.rocket_launch),
            label: const Text('Present Onboarding'),
          ),
          const SizedBox(height: 12),

          // Remote Config
          FilledButton.icon(
            onPressed: () async {
              final value = await AppDNA.getRemoteConfig('welcome_message');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Remote config: $value')),
                );
              }
            },
            icon: const Icon(Icons.settings_remote),
            label: const Text('Get Remote Config'),
          ),
          const SizedBox(height: 12),

          // Experiment Variant
          FilledButton.icon(
            onPressed: () async {
              final variant = await AppDNA.getExperimentVariant('onboarding_test');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Variant: $variant')),
                );
              }
            },
            icon: const Icon(Icons.science),
            label: const Text('Get Experiment Variant'),
          ),
          const SizedBox(height: 12),

          // Feature Flag
          FilledButton.icon(
            onPressed: () async {
              final enabled = await AppDNA.isFeatureEnabled('dark_mode');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Feature enabled: $enabled')),
                );
              }
            },
            icon: const Icon(Icons.flag),
            label: const Text('Check Feature Flag'),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value),
      ),
    );
  }
}
