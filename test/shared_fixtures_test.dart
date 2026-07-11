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
// WHAT THIS RUNNER MAY CLAIM
// --------------------------
// 🔴 It used to claim 37 fixtures and assert ONE. Two sat in a `knownDriverGaps` set and the other
// 34 fell through `default:` to a "soft skip" that printed a line and RETURNED from inside the
// `test()` body — so Dart printed a tick for each. Every paywall, purchase, restore and push fixture
// was a green no-op; emptying `AppDNA.presentPaywall` broke nothing. The one hard-skipped
// `track_event` fixture was hiding a real bug: the driver read `action['event']` when the fixture key
// is `event_name`.
//
// The rule now: a thin wrapper FORWARDS, so forwarding is the only thing it can prove. A fixture
// whose `expect` describes native behaviour — a form advancing, a purchase failure being typed, a
// push routing to a deep link — is a NATIVE fixture, and its `platforms` list must say so. This
// runner drives the fixtures whose subject is marshalling (`track_event`, `identify`), and an action
// kind it has no driver for is a FAILURE, never a skip.
//
// `check:fixture-runner-skips` enforces exactly that: no skiplist, no soft-skip, fatal fallback.
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
    final category = (json['category'] as String?) ?? '';
    // `render` (SPEC-419) and `events` (SPEC-428) fixtures carry no `action` — this behavioral runner
    // requires one. The event pipeline is native-owned (ADR-001), so its guarantees are asserted by the
    // iOS + Android EventPipeline runners; the Flutter thin wrapper only forwards track() to native.
    if (platforms.contains('flutter') && category != 'render' && category != 'events') {
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
      // The fixture key is `event_name`. This read `action['event']` — always null — and papered
      // over it with `?? 'unknown'`, so it tracked a made-up event and then asserted
      // `args['event'] == action['event']`, i.e. 'unknown' == null. That would have failed loudly,
      // which is presumably why the ONLY track_event fixture sat in `knownDriverGaps`. A missing key
      // is a broken fixture; say so rather than inventing a name.
      final event = action['event_name'] as String?;
      if (event == null) {
        fail('[${fixture['id']}] track_event fixture has no `event_name`');
      }
      await AppDNA.track(event, properties: action['properties'] as Map<String, dynamic>?);
      break;
    case 'identify':
      final userId = action['userId'] as String?;
      if (userId == null) {
        fail('[${fixture['id']}] identify fixture has no `userId`');
      }
      await AppDNA.identify(userId, traits: action['traits'] as Map<String, dynamic>?);
      break;
    default:
      // 🔴 This used to record a skip reason and let the test PASS. 34 of the 37 fixtures that
      // claimed `flutter` came through here and printed a tick — every paywall, purchase, restore
      // and push fixture among them. Emptying `AppDNA.presentPaywall` left all five paywall
      // fixtures green.
      //
      // A fixture this runner cannot drive is not a fixture this runner may pass. The wrapper is
      // thin: it forwards, so it can only ever prove FORWARDING. Anything asserting native
      // behaviour (rendering a form, typing a purchase failure, routing a push) is a native
      // fixture, and its `platforms` list must not claim `flutter`.
      fail(
        '[${fixture['id']}] no Flutter driver for action.kind=$kind. Either add one, or remove '
        '"flutter" from this fixture\'s platforms — it asserts behaviour the wrapper does not have.',
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
      expect(args['event'], action['event_name'], reason: '[$id] track event name');
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
      fail('[$id] no channel-contract assertion registered for action.kind=$kind');
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

  // SPEC-070-0 / SPEC-070-A — Flutter 3.41+ throws `OutsideTestException` for
  // any `expect()` invoked outside a `test()` block. Promote the runner-self-
  // check to its own `test()` so the assertion still runs but inside the test
  // framework. Empty fixtures => single failing test, not a load-time crash.
  test('runner self-check: flutter-applicable fixtures discovered', () {
    expect(fixtures, isNotEmpty,
        reason: 'No flutter-applicable fixtures found — runner is broken');
  });

  group('SharedFixtures (Flutter channel contract)', () {
    for (final fixture in fixtures) {
      final id = fixture['id'] as String;
      final description = fixture['description'] as String;
      test('$id — $description', () async {
        await _runFixture(fixture, spy);
        _assertChannelCalls(fixture, spy);
      });
    }
  });
}
