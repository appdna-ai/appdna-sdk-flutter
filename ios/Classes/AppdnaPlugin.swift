import Flutter
import UIKit
import AppDNASDK

public class AppdnaPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var billingChannel: FlutterMethodChannel?
    // fileprivate so BillingEntitlementStreamHandler (same file) can route the
    // entitlement stream through it. Not public — stays internal to this file.
    fileprivate var entitlementEventSink: FlutterEventSink?

    // MARK: - Delegate forwarders (strong references so they are NOT
    // deallocated — the iOS SDK holds delegates with `weak` semantics on
    // most surfaces and `static weak` on push/billing/screen).
    private var onboardingForwarder: OnboardingDelegateForwarder?
    private var paywallForwarder: PaywallDelegateForwarder?
    private var surveyForwarder: SurveyDelegateForwarder?
    private var inAppMessageForwarder: InAppMessageDelegateForwarder?
    private var pushForwarder: PushDelegateForwarder?
    private var billingDelegateForwarder: BillingDelegateForwarder?
    private var deepLinkForwarder: DeepLinkDelegateForwarder?
    private var screenForwarder: ScreenDelegateForwarder?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.appdna.sdk/main",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.appdna.sdk/web_entitlement",
            binaryMessenger: registrar.messenger()
        )

        // Billing channels
        let billingChannel = FlutterMethodChannel(
            name: "com.appdna.sdk/billing",
            binaryMessenger: registrar.messenger()
        )
        let entitlementEventChannel = FlutterEventChannel(
            name: "com.appdna.sdk/entitlements",
            binaryMessenger: registrar.messenger()
        )

        let instance = AppdnaPlugin()
        instance.billingChannel = billingChannel
        registrar.addMethodCallDelegate(instance, channel: channel)
        billingChannel.setMethodCallHandler(instance.handleBilling)
        eventChannel.setStreamHandler(instance)
        entitlementEventChannel.setStreamHandler(BillingEntitlementStreamHandler(plugin: instance))

        // MARK: - Delegate event channels (native -> Dart)
        // Each forwarder implements the corresponding native delegate
        // protocol AND FlutterStreamHandler. On stream onListen the
        // forwarder is wired to the native module via setDelegate(...);
        // on onCancel the delegate is cleared.
        let messenger = registrar.messenger()

        let onboardingChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/onboarding", binaryMessenger: messenger
        )
        let onboardingForwarder = OnboardingDelegateForwarder()
        instance.onboardingForwarder = onboardingForwarder
        onboardingChannel.setStreamHandler(onboardingForwarder)

        let paywallChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/paywall", binaryMessenger: messenger
        )
        let paywallForwarder = PaywallDelegateForwarder()
        instance.paywallForwarder = paywallForwarder
        paywallChannel.setStreamHandler(paywallForwarder)

        let surveyChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/survey", binaryMessenger: messenger
        )
        let surveyForwarder = SurveyDelegateForwarder()
        instance.surveyForwarder = surveyForwarder
        surveyChannel.setStreamHandler(surveyForwarder)

        let inAppMessageChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/in_app_message", binaryMessenger: messenger
        )
        let inAppMessageForwarder = InAppMessageDelegateForwarder()
        instance.inAppMessageForwarder = inAppMessageForwarder
        inAppMessageChannel.setStreamHandler(inAppMessageForwarder)

        let pushChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/push", binaryMessenger: messenger
        )
        let pushForwarder = PushDelegateForwarder()
        instance.pushForwarder = pushForwarder
        pushChannel.setStreamHandler(pushForwarder)

        let billingEventChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/billing", binaryMessenger: messenger
        )
        let billingDelegateForwarder = BillingDelegateForwarder()
        instance.billingDelegateForwarder = billingDelegateForwarder
        billingEventChannel.setStreamHandler(billingDelegateForwarder)

        let deepLinkChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/deep_link", binaryMessenger: messenger
        )
        let deepLinkForwarder = DeepLinkDelegateForwarder()
        instance.deepLinkForwarder = deepLinkForwarder
        deepLinkChannel.setStreamHandler(deepLinkForwarder)

        let screenChannel = FlutterEventChannel(
            name: "com.appdna.sdk/events/screen", binaryMessenger: messenger
        )
        let screenForwarder = ScreenDelegateForwarder()
        instance.screenForwarder = screenForwarder
        screenChannel.setStreamHandler(screenForwarder)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "configure":
            let apiKey = args["apiKey"] as! String
            let envStr = args["env"] as? String ?? "production"
            let env: Environment = envStr == "staging" ? .sandbox : .production
            let options = parseOptions(args["options"] as? [String: Any])
            AppDNA.configure(apiKey: apiKey, environment: env, options: options)
            result(nil)

        case "identify":
            let userId = args["userId"] as! String
            let traits = args["traits"] as? [String: Any]
            AppDNA.identify(userId: userId, traits: traits)
            result(nil)

        case "reset":
            AppDNA.reset()
            result(nil)

        case "track":
            let event = args["event"] as! String
            let properties = args["properties"] as? [String: Any]
            AppDNA.track(event: event, properties: properties)
            result(nil)

        case "flush":
            AppDNA.flush()
            result(nil)

        case "presentPaywall":
            let id = args["id"] as! String
            let context = parsePaywallContext(args["context"] as? [String: Any])
            if let vc = UIApplication.shared.topViewController {
                AppDNA.presentPaywall(id: id, from: vc, context: context)
            }
            result(nil)

        case "presentOnboarding":
            let flowId = args["flowId"] as? String
            AppDNA.presentOnboarding(flowId: flowId)
            result(nil)

        case "getRemoteConfig":
            let key = args["key"] as! String
            result(AppDNA.getRemoteConfig(key: key))

        case "isFeatureEnabled":
            let flag = args["flag"] as! String
            result(AppDNA.isFeatureEnabled(flag: flag))

        case "getExperimentVariant":
            let experimentId = args["experimentId"] as! String
            result(AppDNA.getExperimentVariant(experimentId: experimentId))

        case "isInVariant":
            let experimentId = args["experimentId"] as! String
            let variantId = args["variantId"] as! String
            result(AppDNA.isInVariant(experimentId: experimentId, variantId: variantId))

        case "getExperimentConfig":
            let experimentId = args["experimentId"] as! String
            let key = args["key"] as! String
            result(AppDNA.getExperimentConfig(experimentId: experimentId, key: key))

        case "setPushToken":
            if let tokenStr = args["token"] as? String,
               let tokenData = hexStringToData(tokenStr) {
                AppDNA.setPushToken(tokenData)
            }
            result(nil)

        case "setPushPermission":
            let granted = args["granted"] as? Bool ?? false
            AppDNA.setPushPermission(granted: granted)
            result(nil)

        case "trackPushDelivered":
            let pushId = args["pushId"] as! String
            AppDNA.trackPushDelivered(pushId: pushId)
            result(nil)

        case "trackPushTapped":
            let pushId = args["pushId"] as! String
            let action = args["action"] as? String
            AppDNA.trackPushTapped(pushId: pushId, action: action)
            result(nil)

        case "setConsent":
            let analytics = args["analytics"] as? Bool ?? true
            AppDNA.setConsent(analytics: analytics)
            result(nil)

        case "onReady":
            AppDNA.onReady {
                result(true)
            }

        case "getWebEntitlement":
            if let entitlement = AppDNA.webEntitlement {
                result(entitlement.toMap())
            } else {
                result(nil)
            }

        case "checkDeferredDeepLink":
            AppDNA.checkDeferredDeepLink { deepLink in
                if let deepLink = deepLink {
                    result(deepLink.toMap())
                } else {
                    result(nil)
                }
            }

        case "shutdown":
            // iOS SDK does not expose a shutdown method; resolve immediately.
            result(nil)

        case "getSdkVersion":
            result(AppDNA.sdkVersion)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers

    private func hexStringToData(_ hex: String) -> Data? {
        let len = hex.count
        guard len % 2 == 0 else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        return data
    }

    private func parseOptions(_ dict: [String: Any]?) -> AppDNAOptions {
        guard let dict = dict else { return AppDNAOptions() }
        let logLevelStr = dict["logLevel"] as? String ?? "warning"
        let logLevel: LogLevel
        switch logLevelStr {
        case "none": logLevel = .none
        case "error": logLevel = .error
        case "warning": logLevel = .warning
        case "info": logLevel = .info
        case "debug": logLevel = .debug
        default: logLevel = .warning
        }

        let billingProviderStr = dict["billingProvider"] as? String
        let billingProvider: BillingProvider
        switch billingProviderStr {
        case "revenueCat": billingProvider = .revenueCat
        case "storeKit2": billingProvider = .storeKit2
        case "none": billingProvider = .none
        default: billingProvider = .storeKit2
        }

        return AppDNAOptions(
            flushInterval: dict["flushInterval"] as? TimeInterval ?? 30,
            batchSize: dict["batchSize"] as? Int ?? 20,
            configTTL: dict["configTTL"] as? TimeInterval ?? 300,
            logLevel: logLevel,
            billingProvider: billingProvider
        )
    }

    private func parsePaywallContext(_ dict: [String: Any]?) -> PaywallContext? {
        guard let dict = dict, let placement = dict["placement"] as? String else { return nil }
        return PaywallContext(
            placement: placement,
            experiment: dict["experiment"] as? String,
            variant: dict["variant"] as? String
        )
    }

    // MARK: - Billing method channel handler

    private func handleBilling(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "purchase":
            let productId = args["productId"] as! String
            // `offerToken` is an Android (Play Billing base-plan/offer) concept.
            // iOS StoreKit has no equivalent, so it is accepted from the channel
            // for API symmetry but not forwarded to the native call.
            Task {
                do {
                    // Native signature (AppDNASDK 1.0.67):
                    //   purchase(_ productId: String, options: PurchaseOptions?) -> TransactionInfo
                    // Throws on user-cancel / pending. Mirror the Android
                    // semantics: success -> {status:"purchased", entitlement},
                    // cancel -> {status:"cancelled"}.
                    let transaction = try await AppDNA.billing.purchase(productId)
                    DispatchQueue.main.async {
                        result(transaction.toPurchaseResultMap())
                    }
                } catch {
                    DispatchQueue.main.async {
                        if BillingMappers.isUserCancellation(error) {
                            result(["status": "cancelled"])
                        } else {
                            result(FlutterError(code: "PURCHASE_ERROR", message: error.localizedDescription, details: nil))
                        }
                    }
                }
            }

        case "restorePurchases":
            Task {
                do {
                    // Native `restorePurchases()` now returns restored product IDs
                    // ([String]). To preserve the Dart `List<Entitlement>` contract
                    // we trigger the restore, then return the current entitlements.
                    _ = try await AppDNA.billing.restorePurchases()
                    let entitlements = await AppDNA.billing.getEntitlements()
                    let maps = entitlements.map { $0.toFlutterMap() }
                    DispatchQueue.main.async {
                        result(maps)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "RESTORE_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "getProducts":
            let productIds = args["productIds"] as? [String] ?? []
            Task {
                do {
                    // Native signature: getProducts(_ ids: [String]) -> [ProductInfo]
                    let products = try await AppDNA.billing.getProducts(productIds)
                    let maps = products.map { $0.toFlutterMap() }
                    DispatchQueue.main.async {
                        result(maps)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "PRODUCTS_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "hasActiveSubscription":
            Task {
                let hasActive = await AppDNA.billing.hasActiveSubscription()
                DispatchQueue.main.async {
                    result(hasActive)
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler (web entitlement events)

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        AppDNA.onWebEntitlementChanged { [weak self] entitlement in
            self?.eventSink?(entitlement?.toMap())
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

// MARK: - Billing entitlement stream handler

private class BillingEntitlementStreamHandler: NSObject, FlutterStreamHandler {
    weak var plugin: AppdnaPlugin?

    init(plugin: AppdnaPlugin) {
        self.plugin = plugin
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.entitlementEventSink = events
        AppDNA.billing.onEntitlementsChanged { [weak self] entitlements in
            let maps = entitlements.map { $0.toFlutterMap() }
            self?.plugin?.entitlementEventSink?(maps)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.entitlementEventSink = nil
        return nil
    }
}

// MARK: - UIApplication helper

private extension UIApplication {
    var topViewController: UIViewController? {
        guard let scene = connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var vc = root
        while let presented = vc.presentedViewController {
            vc = presented
        }
        return vc
    }
}

// MARK: - Delegate Event Forwarders
//
// Each forwarder implements one of the eight native delegate protocols
// AND FlutterStreamHandler. On stream `onListen` it wires itself into
// the native module via `setDelegate(...)`; on `onCancel` it clears the
// delegate. Every callback marshals its arguments into the canonical
// shared payload:
//
//   { "type": "<delegateMethodName>", "args": { "<argName>": <value>, ... } }
//
// and dispatches `eventSink(...)` on the main thread (required by Flutter).
//
// All forwarders are held strongly by `AppdnaPlugin` so they survive the
// iOS SDK's `weak` delegate references.

/// Convenience: serialize a Swift `Error` for Dart consumers.
@inline(__always)
private func errorMap(_ error: Error) -> [String: Any] {
    return [
        "message": error.localizedDescription,
        "type": "\(type(of: error))"
    ]
}

/// Convenience: dispatch a `{type,args}` payload to a sink on main thread.
@inline(__always)
private func sendEvent(_ sink: FlutterEventSink?, type: String, args: [String: Any?]) {
    guard let sink = sink else { return }
    let payload: [String: Any] = [
        "type": type,
        "args": args.mapValues { $0 ?? NSNull() }
    ]
    if Thread.isMainThread {
        sink(payload)
    } else {
        DispatchQueue.main.async {
            sink(payload)
        }
    }
}

// MARK: Onboarding

private class OnboardingDelegateForwarder: NSObject, AppDNAOnboardingDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.onboarding.setDelegate(self)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.onboarding.setDelegate(nil)
        self.sink = nil
        return nil
    }

    func onOnboardingStarted(flowId: String) {
        sendEvent(sink, type: "onOnboardingStarted", args: ["flowId": flowId])
    }

    func onOnboardingStepChanged(flowId: String, stepId: String, stepIndex: Int, totalSteps: Int) {
        sendEvent(sink, type: "onOnboardingStepChanged", args: [
            "flowId": flowId,
            "stepId": stepId,
            "stepIndex": stepIndex,
            "totalSteps": totalSteps
        ])
    }

    func onOnboardingCompleted(flowId: String, responses: [String: Any]) {
        sendEvent(sink, type: "onOnboardingCompleted", args: [
            "flowId": flowId,
            "responses": responses
        ])
    }

    func onOnboardingDismissed(flowId: String, atStep: Int) {
        sendEvent(sink, type: "onOnboardingDismissed", args: [
            "flowId": flowId,
            "atStep": atStep
        ])
    }

    // SPEC-083 async hooks: forward as observe-only events for visibility,
    // but return the default values. Sync-veto / async-return bridging is
    // a follow-up (see InAppMessage.shouldShowMessage note below).
    func onBeforeStepAdvance(
        flowId: String,
        fromStepId: String,
        stepIndex: Int,
        stepType: String,
        responses: [String: Any],
        stepData: [String: Any]?
    ) async -> StepAdvanceResult {
        sendEvent(sink, type: "onBeforeStepAdvance", args: [
            "flowId": flowId,
            "fromStepId": fromStepId,
            "stepIndex": stepIndex,
            "stepType": stepType,
            "responses": responses,
            "stepData": stepData
        ])
        return .proceed
    }

    func onBeforeStepRender(
        flowId: String,
        stepId: String,
        stepIndex: Int,
        stepType: String,
        responses: [String: Any]
    ) async -> StepConfigOverride? {
        sendEvent(sink, type: "onBeforeStepRender", args: [
            "flowId": flowId,
            "stepId": stepId,
            "stepIndex": stepIndex,
            "stepType": stepType,
            "responses": responses
        ])
        return nil
    }
}

// MARK: Paywall

private class PaywallDelegateForwarder: NSObject, AppDNAPaywallDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.paywall.setDelegate(self)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.paywall.setDelegate(nil)
        self.sink = nil
        return nil
    }

    func onPaywallPresented(paywallId: String) {
        sendEvent(sink, type: "onPaywallPresented", args: ["paywallId": paywallId])
    }

    func onPaywallAction(paywallId: String, action: PaywallAction) {
        sendEvent(sink, type: "onPaywallAction", args: [
            "paywallId": paywallId,
            "action": action.rawValue
        ])
    }

    func onPaywallPurchaseStarted(paywallId: String, productId: String) {
        sendEvent(sink, type: "onPaywallPurchaseStarted", args: [
            "paywallId": paywallId,
            "productId": productId
        ])
    }

    func onPaywallPurchaseCompleted(paywallId: String, productId: String, transaction: TransactionInfo) {
        sendEvent(sink, type: "onPaywallPurchaseCompleted", args: [
            "paywallId": paywallId,
            "productId": productId,
            "transaction": transactionInfoToMap(transaction)
        ])
    }

    func onPaywallPurchaseFailed(paywallId: String, error: Error) {
        sendEvent(sink, type: "onPaywallPurchaseFailed", args: [
            "paywallId": paywallId,
            "error": errorMap(error)
        ])
    }

    func onPaywallDismissed(paywallId: String) {
        sendEvent(sink, type: "onPaywallDismissed", args: ["paywallId": paywallId])
    }

    func onPromoCodeSubmit(paywallId: String, code: String, completion: @escaping (Bool) -> Void) {
        // Forward as observe-only for v1; default-reject the code since
        // we can't synchronously await a Dart response. Sync-return
        // bridging is a follow-up (documented in plugin scope).
        sendEvent(sink, type: "onPromoCodeSubmit", args: [
            "paywallId": paywallId,
            "code": code
        ])
        completion(false)
    }

    func onPostPurchaseDeepLink(paywallId: String, url: String) {
        sendEvent(sink, type: "onPostPurchaseDeepLink", args: [
            "paywallId": paywallId,
            "url": url
        ])
    }

    func onPostPurchaseNextStep(paywallId: String) {
        sendEvent(sink, type: "onPostPurchaseNextStep", args: ["paywallId": paywallId])
    }

    func onPaywallRestoreStarted(paywallId: String) {
        sendEvent(sink, type: "onPaywallRestoreStarted", args: ["paywallId": paywallId])
    }

    func onPaywallRestoreCompleted(paywallId: String, productIds: [String]) {
        sendEvent(sink, type: "onPaywallRestoreCompleted", args: [
            "paywallId": paywallId,
            "productIds": productIds
        ])
    }

    func onPaywallRestoreFailed(paywallId: String, error: Error) {
        sendEvent(sink, type: "onPaywallRestoreFailed", args: [
            "paywallId": paywallId,
            "error": errorMap(error)
        ])
    }

    private func transactionInfoToMap(_ t: TransactionInfo) -> [String: Any] {
        return [
            "transactionId": t.transactionId,
            "productId": t.productId,
            "purchaseDate": t.purchaseDate.timeIntervalSince1970 * 1000,
            "environment": t.environment
        ]
    }
}

// MARK: Survey

private class SurveyDelegateForwarder: NSObject, AppDNASurveyDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.surveys.setDelegate(self)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.surveys.setDelegate(nil)
        self.sink = nil
        return nil
    }

    func onSurveyPresented(surveyId: String) {
        sendEvent(sink, type: "onSurveyPresented", args: ["surveyId": surveyId])
    }

    func onSurveyCompleted(surveyId: String, responses: [SurveyResponse]) {
        let mapped: [[String: Any]] = responses.map { r in
            ["questionId": r.questionId, "answer": r.answer]
        }
        sendEvent(sink, type: "onSurveyCompleted", args: [
            "surveyId": surveyId,
            "responses": mapped
        ])
    }

    func onSurveyDismissed(surveyId: String) {
        sendEvent(sink, type: "onSurveyDismissed", args: ["surveyId": surveyId])
    }
}

// MARK: In-App Message

private class InAppMessageDelegateForwarder: NSObject, AppDNAInAppMessageDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.inAppMessages.setDelegate(self)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.inAppMessages.setDelegate(nil)
        self.sink = nil
        return nil
    }

    func onMessageShown(messageId: String, trigger: String) {
        sendEvent(sink, type: "onMessageShown", args: [
            "messageId": messageId,
            "trigger": trigger
        ])
    }

    func onMessageAction(messageId: String, action: String, data: [String: Any]?) {
        sendEvent(sink, type: "onMessageAction", args: [
            "messageId": messageId,
            "action": action,
            "data": data
        ])
    }

    func onMessageDismissed(messageId: String) {
        sendEvent(sink, type: "onMessageDismissed", args: ["messageId": messageId])
    }

    /// VETO method — `shouldShowMessage(messageId:) -> Bool` is synchronous
    /// and cannot wait on a Dart roundtrip. v1 forwards the message as an
    /// observe-only event on the in_app_message channel and defaults the
    /// return value to `true` (always show). Sync veto bridging via a
    /// blocking MethodChannel call from Dart is a follow-up.
    func shouldShowMessage(messageId: String) -> Bool {
        sendEvent(sink, type: "shouldShowMessage", args: ["messageId": messageId])
        return true
    }
}

// MARK: Push

private class PushDelegateForwarder: NSObject, AppDNAPushDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.pushModule.setDelegate(self)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.pushModule.setDelegate(nil)
        self.sink = nil
        return nil
    }

    func onPushTokenRegistered(token: String) {
        sendEvent(sink, type: "onPushTokenRegistered", args: ["token": token])
    }

    func onPushReceived(notification: PushPayload, inForeground: Bool) {
        sendEvent(sink, type: "onPushReceived", args: [
            "notification": pushPayloadToMap(notification),
            "inForeground": inForeground
        ])
    }

    func onPushTapped(notification: PushPayload, actionId: String?) {
        sendEvent(sink, type: "onPushTapped", args: [
            "notification": pushPayloadToMap(notification),
            "actionId": actionId
        ])
    }

    private func pushPayloadToMap(_ p: PushPayload) -> [String: Any?] {
        var actionMap: [String: Any]? = nil
        if let a = p.action {
            actionMap = ["type": a.type, "value": a.value]
        }
        return [
            "pushId": p.pushId,
            "title": p.title,
            "body": p.body,
            "imageUrl": p.imageUrl,
            "data": p.data,
            "action": actionMap
        ]
    }
}

// MARK: Billing (lifecycle delegate)

private class BillingDelegateForwarder: NSObject, AppDNABillingDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.billing.setDelegate(self)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.billing.setDelegate(nil)
        self.sink = nil
        return nil
    }

    func onPurchaseCompleted(productId: String, transaction: TransactionInfo) {
        sendEvent(sink, type: "onPurchaseCompleted", args: [
            "productId": productId,
            "transaction": [
                "transactionId": transaction.transactionId,
                "productId": transaction.productId,
                "purchaseDate": transaction.purchaseDate.timeIntervalSince1970 * 1000,
                "environment": transaction.environment
            ]
        ])
    }

    func onPurchaseFailed(productId: String, error: Error) {
        sendEvent(sink, type: "onPurchaseFailed", args: [
            "productId": productId,
            "error": errorMap(error)
        ])
    }

    func onEntitlementsChanged(entitlements: [Entitlement]) {
        let mapped: [[String: Any?]] = entitlements.map { e in
            [
                "identifier": e.identifier,
                "isActive": e.isActive,
                "expiresAt": e.expiresAt.map { $0.timeIntervalSince1970 * 1000 },
                "productId": e.productId
            ]
        }
        sendEvent(sink, type: "onEntitlementsChanged", args: [
            "entitlements": mapped
        ])
    }

    func onRestoreCompleted(restoredProducts: [String]) {
        sendEvent(sink, type: "onRestoreCompleted", args: [
            "restoredProducts": restoredProducts
        ])
    }
}

// MARK: Deep Link

private class DeepLinkDelegateForwarder: NSObject, AppDNADeepLinkDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.deepLinks.setDelegate(self)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.deepLinks.setDelegate(nil)
        self.sink = nil
        return nil
    }

    func onDeepLinkReceived(url: URL, params: [String: String]) {
        sendEvent(sink, type: "onDeepLinkReceived", args: [
            "url": url.absoluteString,
            "params": params
        ])
    }
}

// MARK: Screen
//
// The Screen delegate is held on `AppDNA.screenDelegate` (static weak),
// not via a module-level `setDelegate(...)`. The forwarder is kept alive
// by `AppdnaPlugin` and assigned/cleared on stream lifecycle.

private class ScreenDelegateForwarder: NSObject, AppDNAScreenDelegate, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        AppDNA.screenDelegate = self
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppDNA.screenDelegate = nil
        self.sink = nil
        return nil
    }

    func onScreenPresented(screenId: String) {
        sendEvent(sink, type: "onScreenPresented", args: ["screenId": screenId])
    }

    func onScreenDismissed(screenId: String, result: ScreenResult) {
        sendEvent(sink, type: "onScreenDismissed", args: [
            "screenId": screenId,
            "result": screenResultToMap(result)
        ])
    }

    func onFlowCompleted(flowId: String, result: FlowResult) {
        sendEvent(sink, type: "onFlowCompleted", args: [
            "flowId": flowId,
            "result": flowResultToMap(result)
        ])
    }

    /// VETO method — `onScreenAction(screenId:action:) -> Bool` is
    /// synchronous; v1 forwards as observe-only and defaults to `true`
    /// (allow the action). Sync veto bridging is a follow-up.
    func onScreenAction(screenId: String, action: SectionAction) -> Bool {
        sendEvent(sink, type: "onScreenAction", args: [
            "screenId": screenId,
            "action": sectionActionToMap(action)
        ])
        return true
    }

    private func screenResultToMap(_ r: ScreenResult) -> [String: Any?] {
        return [
            "screenId": r.screenId,
            "dismissed": r.dismissed,
            "responses": r.responses,
            "lastAction": r.lastAction,
            "duration_ms": r.duration_ms,
            "error": r.error?.rawValue
        ]
    }

    private func flowResultToMap(_ r: FlowResult) -> [String: Any?] {
        return [
            "flowId": r.flowId,
            "completed": r.completed,
            "lastScreenId": r.lastScreenId,
            "responses": r.responses,
            "screensViewed": r.screensViewed,
            "duration_ms": r.duration_ms,
            "error": r.error?.rawValue
        ]
    }

    /// Encode a `SectionAction` as `{type, value?}` matching the shared
    /// payload contract (Android forwarder encodes the same shape).
    private func sectionActionToMap(_ action: SectionAction) -> [String: Any?] {
        switch action {
        case .next:
            return ["type": "next"]
        case .back:
            return ["type": "back"]
        case .dismiss:
            return ["type": "dismiss"]
        case .navigate(let screenId):
            return ["type": "navigate", "screenId": screenId]
        case .openURL(let url):
            return ["type": "openURL", "url": url]
        case .openWebview(let url):
            return ["type": "openWebview", "url": url]
        case .openAppSettings:
            return ["type": "openAppSettings"]
        case .share(let text):
            return ["type": "share", "text": text]
        case .deepLink(let url):
            return ["type": "deepLink", "url": url]
        case .showPaywall(let id):
            return ["type": "showPaywall", "id": id]
        case .showSurvey(let id):
            return ["type": "showSurvey", "id": id]
        case .showScreen(let id):
            return ["type": "showScreen", "id": id]
        case .submitForm(let data):
            return ["type": "submitForm", "data": data]
        case .track(let event, let properties):
            return ["type": "track", "event": event, "properties": properties]
        case .haptic(let type):
            return ["type": "haptic", "hapticType": type]
        case .custom(let type, let value):
            return ["type": "custom", "customType": type, "value": value]
        }
    }
}
