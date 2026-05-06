// shared_fixtures_test.dart
//
// Cross-platform behavioral fixture runner for Flutter — SPEC-070-0 §3.2 + §3.3 step 6.
//
// Per ADR-001 the Flutter Dart layer is a THIN WRAPPER. This runner therefore
// verifies the **channel contract**: for each fixture's `action`, calling the
// SDK Dart facade triggers the expected `MethodChannel.invokeMethod(...)`
// sequence with the right method name + args. Channel calls are spied via
// `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
// .setMockMethodCallHandler` on the SDK's main channel.
//
// The actual events / delegate_calls / state_after assertions in `expect`
// are validated by the iOS + Android runners (which exercise real native
// SDK code paths). The Flutter runner asserts the wrapper produces the
// CORRECT CHANNEL CALL — i.e. the input-side of the contract.
//
// PHASE 0.4 SCAFFOLDING NOTE
// ---------------------------
// The Dart facade does not yet expose every action kind we have fixtures
// for (the SDK is intentionally narrow today — see SPEC-070-C catchup
// queue). The kinds wired through Phase 0.4:
//
//   - track_event   → AppDNA.track(...)         — channel: "track"
//   - identify      → AppDNA.identify(...)      — channel: "identify"
//   - tap_button    → SKIP (no host-driven UI tap simulation in the
//                          Dart facade today; v1.0.60 dual-emit is
//                          purely native-side. Asserted by iOS+Android.)
//   - submit_form   → SKIP (same — onboarding render is native)
//   - evaluate_audience → SKIP (native-only API surface)
//
// All other kinds emit a soft skip with reason "Phase 0.5+ assertion
// not yet implemented." CI stays green; the skip count is the Phase 0.5
// remaining-work gauge.
//
// FIXTURE PATH RESOLUTION
// -----------------------
// Flutter doesn't easily ship sibling-package JSON resources; an asset
// declaration in `pubspec.yaml` is the proper fix but requires copying
// fixtures into the package or adding a build step. Until then:
//   1. `APPDNA_SDK_FIXTURES_DIR` env var (CI sets this absolute path)
//   2. Walk up from the test cwd until `packages/sdk-shared-fixtures/`
//      is found
//   3. Codespace fallback: `/workspaces/appdna-ai/packages/sdk-shared-fixtures`
//
// © 2026 AppDNA AI, Inc.

import 'dart:convert';
import 'dart:io';

import 'package:appdna_sdk/appdna_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturedCall {
  _CapturedCall(this.method, this.arguments);
  final String method;
  final dynamic arguments;
}

class _Spy {
  final List<_CapturedCall> calls = <_CapturedCall>[];
  final List<String> skipReasons = <String>[];
}

Directory _resolveFixturesRoot() {
  final env = Platform.environment['APPDNA_SDK_FIXTURES_DIR'];
  if (env != null && Directory(env).existsSync()) {
    return Directory(env);
  }
  Directory here = Directory.current;
  for (var i = 0; i < 10; i++) {
    final candidate = Directory(
      '${here.path}${Platform.pathSeparator}packages${Platform.pathSeparator}sdk-shared-fixtures',
    );
    if (candidate.existsSync()) return candidate;
    final parent = here.parent;
    if (parent.path == here.path) break;
    here = parent;
  }
  final codespace = Directory('/workspaces/appdna-ai/packages/sdk-shared-fixtures');
  if (codespace.existsSync()) return codespace;
  throw StateError(
    'Could not locate packages/sdk-shared-fixtures. '
    'Set APPDNA_SDK_FIXTURES_DIR.',
  );
}

List<Map<String, dynamic>> _loadFlutterFixtures() {
  final root = _resolveFixturesRoot();
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.fixture.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final fixtures = <Map<String, dynamic>>[];
  for (final f in files) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final platforms = (json['platforms'] as List).cast<String>();
    if (platforms.contains('flutter')) {
      fixtures.add(json);
    }
  }
  return fixtures;
}

/// Equality that drops down to JSON-string comparison for nested maps/lists,
/// which is sufficient for the channel-arg contract (Flutter MethodChannel
/// preserves shape but not necessarily reference equality).
bool _equivalent(dynamic a, dynamic b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!_equivalent(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_equivalent(a[i], b[i])) return false;
    }
    return true;
  }
  // Coerce to strings to normalize int↔num drift on channel marshalling.
  return a.toString() == b.toString();
}

Future<void> _runFixture(Map<String, dynamic> fixture, _Spy spy) async {
  final action = fixture['action'] as Map<String, dynamic>;
  final kind = action['kind'] as String;

  switch (kind) {
    case 'track_event':
      final event = action['event'] as String? ?? 'unknown';
      final props = action['properties'] as Map<String, dynamic>?;
      await AppDNA.track(event, properties: props);
      break;
    case 'identify':
      final userId = action['userId'] as String? ?? '';
      final traits = action['traits'] as Map<String, dynamic>?;
      await AppDNA.identify(userId, traits: traits);
      break;
    default:
      spy.skipReasons.add(
        'Phase 0.5+ assertion not yet implemented for action.kind=$kind',
      );
  }
}

void _assertChannelCalls(Map<String, dynamic> fixture, _Spy spy) {
  final id = fixture['id'] as String;
  final action = fixture['action'] as Map<String, dynamic>;
  final kind = action['kind'] as String;

  switch (kind) {
    case 'track_event':
      expect(spy.calls, hasLength(1), reason: '[$id] track_event should produce 1 channel call');
      final c = spy.calls.first;
      expect(c.method, 'track', reason: '[$id] expected channel method "track"');
      final args = c.arguments as Map;
      expect(args['event'], action['event'], reason: '[$id] track event name');
      final actualProps = args['properties'];
      final expectedProps = action['properties'];
      expect(
        _equivalent(actualProps, expectedProps),
        isTrue,
        reason: '[$id] track properties: expected=$expectedProps got=$actualProps',
      );
      break;
    case 'identify':
      expect(spy.calls, hasLength(1), reason: '[$id] identify should produce 1 channel call');
      final c = spy.calls.first;
      expect(c.method, 'identify', reason: '[$id] expected channel method "identify"');
      final args = c.arguments as Map;
      expect(args['userId'], action['userId'], reason: '[$id] identify userId');
      final actualTraits = args['traits'];
      final expectedTraits = action['traits'];
      expect(
        _equivalent(actualTraits, expectedTraits),
        isTrue,
        reason: '[$id] identify traits: expected=$expectedTraits got=$actualTraits',
      );
      break;
    default:
      // Skipped — already recorded in spy.skipReasons.
      break;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.appdna.sdk/main');
  late _Spy spy;

  setUp(() {
    spy = _Spy();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      spy.calls.add(_CapturedCall(call.method, call.arguments));
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final fixtures = _loadFlutterFixtures();
  expect(fixtures, isNotEmpty,
      reason: 'No flutter-applicable fixtures found — runner is broken');

  group('SharedFixtures (Flutter channel contract)', () {
    for (final fixture in fixtures) {
      final id = fixture['id'] as String;
      final description = fixture['description'] as String;
      test('$id — $description', () async {
        await _runFixture(fixture, spy);
        if (spy.skipReasons.isNotEmpty) {
          // ignore: avoid_print
          print('[shared_fixtures_test] SKIP $id — ${spy.skipReasons.first}');
          return;
        }
        _assertChannelCalls(fixture, spy);
      });
    }
  });
}
