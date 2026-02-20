import Flutter
import UIKit
import AppDNASDK

public class AppdnaPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var billingChannel: FlutterMethodChannel?
    private var entitlementEventSink: FlutterEventSink?

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
            let offerToken = args["offerToken"] as? String
            Task {
                do {
                    let billingResult = try await AppDNA.billing.purchase(productId: productId, offerToken: offerToken)
                    DispatchQueue.main.async {
                        result(billingResult.toFlutterMap())
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "PURCHASE_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "restorePurchases":
            Task {
                do {
                    let entitlements = try await AppDNA.billing.restorePurchases()
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
                    let products = try await AppDNA.billing.getProducts(productIds: productIds)
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
