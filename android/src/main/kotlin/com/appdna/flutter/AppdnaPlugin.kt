package com.appdna.flutter

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import ai.appdna.sdk.AppDNA
import ai.appdna.sdk.AppDNABillingDelegate
import ai.appdna.sdk.AppDNAInAppMessageDelegate
import ai.appdna.sdk.AppDNAOptions
import ai.appdna.sdk.AppDNAPushDelegate
import ai.appdna.sdk.AppDNADeepLinkDelegate
import ai.appdna.sdk.AppDNASurveyDelegate
import ai.appdna.sdk.Environment
import ai.appdna.sdk.LogLevel
import ai.appdna.sdk.PurchaseCancelledException
import ai.appdna.sdk.PushPayload
import ai.appdna.sdk.SurveyResponse
import ai.appdna.sdk.TransactionInfo
import ai.appdna.sdk.billing.Entitlement
import ai.appdna.sdk.billing.PurchaseOptions
import ai.appdna.sdk.onboarding.AppDNAOnboardingDelegate
import ai.appdna.sdk.onboarding.ElementInteractionResult
import ai.appdna.sdk.onboarding.PermissionHandling
import ai.appdna.sdk.onboarding.StepAdvanceResult
import ai.appdna.sdk.onboarding.StepConfigOverride
import ai.appdna.sdk.paywalls.AppDNAPaywallDelegate
import ai.appdna.sdk.paywalls.PaywallAction
import ai.appdna.sdk.paywalls.PaywallContext
import ai.appdna.sdk.screens.AppDNAScreenDelegate
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import kotlin.coroutines.resume

class AppdnaPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var billingChannel: MethodChannel
    private lateinit var entitlementEventChannel: EventChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var entitlementEventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // SPEC-070-C Phase 2a — native -> Dart sync-callback plumbing. MethodChannel
    // invokes hop onto the main looper (Flutter platform-channel requirement);
    // the coroutine awaits the reply with a timeout-default so a slow/absent
    // Flutter host never deadlocks the native onboarding engine.
    private val mainHandler = Handler(Looper.getMainLooper())
    private val syncCallbackTimeoutMs = 5000L

    // -------------------------------------------------------------------------
    // Native -> Dart delegate event channels (SDK delegate parity).
    //
    // Channel layout per Flutter SDK contract:
    //   com.appdna.sdk/events/<module>          (one-way, native -> Dart)
    //   com.appdna.sdk/sync_callbacks           (MethodChannel for veto hooks)
    //
    // Each event payload is { "type": "<delegateMethodName>", "args": { ... } }.
    // For Throwable args we serialize as { "message": String, "type": String }.
    // Complex DTOs (TransactionInfo, PushPayload, Entitlement) are converted
    // to Map<String, Any?> inline so Flutter's StandardMethodCodec can serialize.
    // -------------------------------------------------------------------------
    private lateinit var paywallEventChannel: EventChannel
    private lateinit var onboardingEventChannel: EventChannel
    private lateinit var surveyEventChannel: EventChannel
    private lateinit var inAppMessageEventChannel: EventChannel
    private lateinit var pushEventChannel: EventChannel
    private lateinit var billingEventChannel: EventChannel
    private lateinit var deepLinkEventChannel: EventChannel
    private lateinit var screenEventChannel: EventChannel
    private lateinit var syncCallbackChannel: MethodChannel

    private var paywallEventSink: EventChannel.EventSink? = null
    private var onboardingEventSink: EventChannel.EventSink? = null
    private var surveyEventSink: EventChannel.EventSink? = null
    private var inAppMessageEventSink: EventChannel.EventSink? = null
    private var pushEventSink: EventChannel.EventSink? = null
    private var billingDelegateEventSink: EventChannel.EventSink? = null
    private var deepLinkEventSink: EventChannel.EventSink? = null
    private var screenEventSink: EventChannel.EventSink? = null

    // Forwarder instances we install on the native modules. Kept as properties
    // so onCancel() can call setDelegate(null) cleanly on stream tear-down.
    private var paywallForwarder: PaywallDelegateForwarder? = null
    private var onboardingForwarder: OnboardingDelegateForwarder? = null
    private var surveyForwarder: SurveyDelegateForwarder? = null
    private var inAppMessageForwarder: InAppMessageDelegateForwarder? = null
    private var pushForwarder: PushDelegateForwarder? = null
    private var billingForwarder: BillingDelegateForwarder? = null
    private var deepLinkForwarder: DeepLinkDelegateForwarder? = null
    private var screenForwarder: ScreenDelegateForwarder? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.appdna.sdk/main")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/web_entitlement")
        eventChannel.setStreamHandler(this)

        // Billing channels
        billingChannel = MethodChannel(binding.binaryMessenger, "com.appdna.sdk/billing")
        billingChannel.setMethodCallHandler { call, result -> handleBilling(call, result) }
        entitlementEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/entitlements")
        entitlementEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                entitlementEventSink = events
                AppDNA.billing.onEntitlementsChanged { entitlements ->
                    val maps = entitlements.map { it.toMap() }
                    entitlementEventSink?.success(maps)
                }
            }
            override fun onCancel(arguments: Any?) {
                entitlementEventSink = null
            }
        })

        // -- Native -> Dart delegate event channels --
        // Eight observe-only streams. onListen wires a forwarder into the
        // native module's setDelegate(); onCancel removes it. The forwarders
        // marshal native callback args into the shared
        // { "type": ..., "args": {...} } envelope and push them through the
        // sink on the main thread.
        paywallEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/paywall")
        paywallEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                paywallEventSink = events
                val fwd = PaywallDelegateForwarder()
                paywallForwarder = fwd
                AppDNA.paywall.setDelegate(fwd)
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.paywall.setDelegate(null)
                paywallForwarder = null
                paywallEventSink = null
            }
        })

        onboardingEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/onboarding")
        onboardingEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                onboardingEventSink = events
                val fwd = OnboardingDelegateForwarder()
                onboardingForwarder = fwd
                // Note: OnboardingModule.setDelegate stores the listener and
                // hands it to AppDNA.presentOnboarding(...) at present-time.
                // Dart code must subscribe to this stream BEFORE calling
                // presentOnboarding() for the callbacks to flow.
                AppDNA.onboarding.setDelegate(fwd)
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.onboarding.setDelegate(null)
                onboardingForwarder = null
                onboardingEventSink = null
            }
        })

        surveyEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/survey")
        surveyEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                surveyEventSink = events
                val fwd = SurveyDelegateForwarder()
                surveyForwarder = fwd
                AppDNA.surveys.setDelegate(fwd)
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.surveys.setDelegate(null)
                surveyForwarder = null
                surveyEventSink = null
            }
        })

        inAppMessageEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/in_app_message")
        inAppMessageEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                inAppMessageEventSink = events
                val fwd = InAppMessageDelegateForwarder()
                inAppMessageForwarder = fwd
                AppDNA.inAppMessages.setDelegate(fwd)
                // SPEC-070-C D10 — register the async shouldShowMessage veto.
                // The native SDK awaits this in ADDITION to the sync delegate
                // veto; invokeDart applies the timeout-default + logs, and a
                // null/timeout reply defaults to allow (true).
                AppDNA.inAppMessages.setAsyncShouldShowMessage { messageId ->
                    (invokeDart("shouldShowMessage", mapOf("messageId" to messageId)) as? Boolean) ?: true
                }
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.inAppMessages.setDelegate(null)
                AppDNA.inAppMessages.setAsyncShouldShowMessage(null)
                inAppMessageForwarder = null
                inAppMessageEventSink = null
            }
        })

        pushEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/push")
        pushEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                pushEventSink = events
                val fwd = PushDelegateForwarder()
                pushForwarder = fwd
                AppDNA.push.setDelegate(fwd)
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.push.setDelegate(null)
                pushForwarder = null
                pushEventSink = null
            }
        })

        billingEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/billing")
        billingEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                billingDelegateEventSink = events
                val fwd = BillingDelegateForwarder()
                billingForwarder = fwd
                AppDNA.billing.setDelegate(fwd)
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.billing.setDelegate(null)
                billingForwarder = null
                billingDelegateEventSink = null
            }
        })

        deepLinkEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/deep_link")
        deepLinkEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deepLinkEventSink = events
                val fwd = DeepLinkDelegateForwarder()
                deepLinkForwarder = fwd
                AppDNA.deepLinks.setDelegate(fwd)
                // SPEC-070-C D10 — register the NET-NEW async shouldOpen veto.
                // The native handleURL() awaits this before dispatching the
                // deep link; null/timeout → allow (open).
                AppDNA.deepLinks.asyncShouldOpen = { url, params ->
                    (invokeDart("shouldOpen", mapOf("url" to url, "params" to params)) as? Boolean) ?: true
                }
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.deepLinks.setDelegate(null)
                AppDNA.deepLinks.asyncShouldOpen = null
                deepLinkForwarder = null
                deepLinkEventSink = null
            }
        })

        screenEventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/events/screen")
        screenEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                screenEventSink = events
                val fwd = ScreenDelegateForwarder()
                screenForwarder = fwd
                AppDNA.screenDelegate = fwd
                // SPEC-070-C D10 — register the async onScreenAction veto. The
                // native SDK awaits this before performing the action (the sync
                // forwarder below always returns true); null/timeout → allow.
                AppDNA.asyncOnScreenAction = { screenId, action ->
                    (invokeDart("onScreenAction", mapOf("screenId" to screenId, "action" to action)) as? Boolean) ?: true
                }
            }
            override fun onCancel(arguments: Any?) {
                AppDNA.screenDelegate = null
                AppDNA.asyncOnScreenAction = null
                screenForwarder = null
                screenEventSink = null
            }
        })

        // Synchronous-veto MethodChannel. v1 only ships the InAppMessage
        // observe path (the veto fires through the in_app_message event
        // channel and the native side defaults shouldShowMessage() to true).
        // Real veto plumbing requires bridging Kotlin sync return -> Dart
        // async invokeMethod -> Kotlin CompletableDeferred, which is left
        // to a follow-up. Channel is registered now so the wire is reserved.
        syncCallbackChannel = MethodChannel(binding.binaryMessenger, "com.appdna.sdk/sync_callbacks")
        syncCallbackChannel.setMethodCallHandler { _, result ->
            // Reserved for future synchronous-veto handshakes from Dart.
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        billingChannel.setMethodCallHandler(null)
        entitlementEventChannel.setStreamHandler(null)
        // Tear down delegate streams and unregister forwarders so the native
        // modules don't keep callbacks alive past Flutter engine teardown.
        paywallEventChannel.setStreamHandler(null)
        onboardingEventChannel.setStreamHandler(null)
        surveyEventChannel.setStreamHandler(null)
        inAppMessageEventChannel.setStreamHandler(null)
        pushEventChannel.setStreamHandler(null)
        billingEventChannel.setStreamHandler(null)
        deepLinkEventChannel.setStreamHandler(null)
        screenEventChannel.setStreamHandler(null)
        syncCallbackChannel.setMethodCallHandler(null)
        runCatching { AppDNA.paywall.setDelegate(null) }
        runCatching { AppDNA.onboarding.setDelegate(null) }
        runCatching { AppDNA.surveys.setDelegate(null) }
        runCatching { AppDNA.inAppMessages.setDelegate(null) }
        runCatching { AppDNA.push.setDelegate(null) }
        runCatching { AppDNA.billing.setDelegate(null) }
        runCatching { AppDNA.deepLinks.setDelegate(null) }
        runCatching { AppDNA.screenDelegate = null }
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> {
                val apiKey = call.argument<String>("apiKey")!!
                val envStr = call.argument<String>("env") ?: "production"
                val env = if (envStr == "staging") Environment.SANDBOX else Environment.PRODUCTION
                val options = parseOptions(call.argument<Map<String, Any>>("options"))
                context?.let { AppDNA.configure(it, apiKey, env, options) }
                result.success(null)
            }
            "identify" -> {
                val userId = call.argument<String>("userId")!!
                val traits = call.argument<Map<String, Any>>("traits")
                AppDNA.identify(userId, traits)
                result.success(null)
            }
            "reset" -> {
                AppDNA.reset()
                result.success(null)
            }
            "track" -> {
                val event = call.argument<String>("event")!!
                val properties = call.argument<Map<String, Any>>("properties")
                AppDNA.track(event, properties)
                result.success(null)
            }
            "flush" -> {
                AppDNA.flush()
                result.success(null)
            }
            "presentPaywall" -> {
                val id = call.argument<String>("id")!!
                val contextMap = call.argument<Map<String, Any>>("context")
                val paywallContext = contextMap?.let { map ->
                    val placement = map["placement"] as? String ?: return@let null
                    PaywallContext(
                        placement = placement,
                        experiment = map["experiment"] as? String,
                        variant = map["variant"] as? String
                    )
                }
                activity?.let { AppDNA.presentPaywall(it, id, paywallContext) }
                result.success(null)
            }
            "presentOnboarding" -> {
                val flowId = call.argument<String>("flowId")!!
                activity?.let { AppDNA.presentOnboarding(it, flowId) }
                result.success(null)
            }
            "getRemoteConfig" -> {
                val key = call.argument<String>("key")!!
                result.success(AppDNA.getRemoteConfig(key))
            }
            "isFeatureEnabled" -> {
                val flag = call.argument<String>("flag")!!
                result.success(AppDNA.isFeatureEnabled(flag))
            }
            "getExperimentVariant" -> {
                val experimentId = call.argument<String>("experimentId")!!
                result.success(AppDNA.getExperimentVariant(experimentId))
            }
            "isInVariant" -> {
                val experimentId = call.argument<String>("experimentId")!!
                val variantId = call.argument<String>("variantId")!!
                result.success(AppDNA.isInVariant(experimentId, variantId))
            }
            "getExperimentConfig" -> {
                val experimentId = call.argument<String>("experimentId")!!
                val key = call.argument<String>("key")!!
                result.success(AppDNA.getExperimentConfig(experimentId, key))
            }
            "setPushToken" -> {
                val token = call.argument<String>("token")!!
                AppDNA.setPushToken(token)
                result.success(null)
            }
            "setPushPermission" -> {
                val granted = call.argument<Boolean>("granted") ?: false
                AppDNA.setPushPermission(granted)
                result.success(null)
            }
            "trackPushDelivered" -> {
                val pushId = call.argument<String>("pushId")!!
                AppDNA.trackPushDelivered(pushId)
                result.success(null)
            }
            "trackPushTapped" -> {
                val pushId = call.argument<String>("pushId")!!
                val action = call.argument<String>("action")
                AppDNA.trackPushTapped(pushId, action)
                result.success(null)
            }
            "setConsent" -> {
                val analytics = call.argument<Boolean>("analytics") ?: true
                AppDNA.setConsent(analytics)
                result.success(null)
            }
            "onReady" -> {
                AppDNA.onReady { result.success(true) }
            }
            "getWebEntitlement" -> {
                val entitlement = AppDNA.webEntitlement
                result.success(entitlement?.toMap())
            }
            "checkDeferredDeepLink" -> {
                AppDNA.checkDeferredDeepLink { deepLink ->
                    result.success(deepLink?.toMap())
                }
            }
            "shutdown" -> {
                AppDNA.shutdown()
                result.success(null)
            }
            "getSdkVersion" -> {
                result.success(AppDNA.sdkVersion)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleBilling(call: MethodCall, result: Result) {
        when (call.method) {
            "purchase" -> {
                val productId = call.argument<String>("productId")!!
                val offerToken = call.argument<String>("offerToken")
                // sdk-android 1.0.39: purchase(activity, productId, options) now
                // requires an Activity (Play Billing launchBillingFlow) and returns
                // a TransactionInfo on success, throwing on cancel/pending/failure.
                val act = activity
                if (act == null) {
                    result.error(
                        "NO_ACTIVITY",
                        "No foreground Activity available to launch the purchase flow",
                        null,
                    )
                    return
                }
                scope.launch {
                    try {
                        val txn = AppDNA.billing.purchase(
                            act,
                            productId,
                            PurchaseOptions(offerToken = offerToken),
                        )
                        // Map TransactionInfo -> Dart PurchaseResult shape
                        // (lib/billing.dart PurchaseResult.fromMap / Entitlement.fromMap).
                        result.success(
                            mapOf(
                                "status" to "purchased",
                                "entitlement" to mapOf(
                                    "productId" to txn.productId,
                                    "store" to "play",
                                    "status" to "active",
                                    "expiresAt" to txn.purchaseDate,
                                    "isTrial" to false,
                                    "offerType" to null,
                                ),
                            ),
                        )
                    } catch (e: PurchaseCancelledException) {
                        result.success(mapOf("status" to "cancelled"))
                    } catch (e: Exception) {
                        // Covers PurchasePending/PurchaseFailed + any billing error.
                        result.error("PURCHASE_ERROR", e.message, null)
                    }
                }
            }
            "restorePurchases" -> {
                // sdk-android 1.0.39: restorePurchases() now returns List<String>
                // (restored product ids). The Dart channel contract still expects
                // List<Entitlement> maps, so trigger the restore then read the
                // refreshed entitlements from the cache.
                scope.launch {
                    try {
                        AppDNA.billing.restorePurchases()
                        val entitlements = AppDNA.billing.getEntitlements()
                        result.success(entitlements.map { it.toMap() })
                    } catch (e: Exception) {
                        result.error("RESTORE_ERROR", e.message, null)
                    }
                }
            }
            "getProducts" -> {
                val productIds = call.argument<List<String>>("productIds") ?: emptyList()
                scope.launch {
                    try {
                        val products = AppDNA.billing.getProducts(productIds)
                        result.success(products.map { it.toMap() })
                    } catch (e: Exception) {
                        result.error("PRODUCTS_ERROR", e.message, null)
                    }
                }
            }
            "hasActiveSubscription" -> {
                scope.launch {
                    try {
                        val hasActive = AppDNA.billing.hasActiveSubscription()
                        result.success(hasActive)
                    } catch (e: Exception) {
                        result.error("SUBSCRIPTION_ERROR", e.message, null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun parseOptions(map: Map<String, Any>?): AppDNAOptions {
        if (map == null) return AppDNAOptions()
        val logLevel = when (map["logLevel"] as? String) {
            "none" -> LogLevel.NONE
            "error" -> LogLevel.ERROR
            "warning" -> LogLevel.WARNING
            "info" -> LogLevel.INFO
            "debug" -> LogLevel.DEBUG
            else -> LogLevel.WARNING
        }
        return AppDNAOptions(
            flushInterval = (map["flushInterval"] as? Number)?.toLong() ?: 30L,
            batchSize = (map["batchSize"] as? Number)?.toInt() ?: 20,
            configTTL = (map["configTTL"] as? Number)?.toLong() ?: 300L,
            logLevel = logLevel
        )
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        AppDNA.onWebEntitlementChanged { entitlement ->
            eventSink?.success(entitlement?.toMap())
        }
    }
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // =========================================================================
    // Native -> Dart delegate forwarders.
    //
    // Each forwarder implements the native delegate interface and pushes a
    // shared { "type": <method>, "args": { ... } } envelope into the matching
    // EventChannel sink. Event sinks are not thread-safe off the main thread,
    // so every send hops onto the main dispatcher via `scope.launch` (the
    // CoroutineScope is built with Dispatchers.Main + SupervisorJob above).
    //
    // For complex DTOs we serialize inline to Map<String, Any?> rather than
    // depending on an extension method `toMap()` that may not exist for every
    // type. Throwables collapse to { "message": String, "type": String }.
    // =========================================================================

    private fun emit(sink: EventChannel.EventSink?, type: String, args: Map<String, Any?>) {
        val target = sink ?: return
        // Coroutine launched on main dispatcher so we can safely call
        // EventChannel.EventSink#success regardless of which thread the
        // native callback fired from.
        scope.launch {
            try {
                target.success(mapOf("type" to type, "args" to args))
            } catch (e: Throwable) {
                // Sink may be closed mid-flight if Dart cancels the stream.
                // Swallow so a stale callback doesn't crash the host app.
            }
        }
    }

    private fun throwableToMap(t: Throwable): Map<String, Any?> = mapOf(
        "message" to (t.message ?: ""),
        "type" to (t::class.java.simpleName ?: "Throwable"),
    )

    private fun transactionToMap(tx: TransactionInfo): Map<String, Any?> = mapOf(
        "transactionId" to tx.transactionId,
        "productId" to tx.productId,
        "purchaseDate" to tx.purchaseDate,
        "environment" to tx.environment,
    )

    private fun entitlementToMap(e: Entitlement): Map<String, Any?> = mapOf(
        "productId" to e.productId,
        "store" to e.store,
        "status" to e.status,
        "expiresAt" to e.expiresAt,
        "isTrial" to e.isTrial,
        "offerType" to e.offerType,
    )

    private fun pushPayloadToMap(p: PushPayload): Map<String, Any?> = mapOf(
        "pushId" to p.pushId,
        "title" to p.title,
        "body" to p.body,
        "imageUrl" to p.imageUrl,
        "data" to p.data,
        "action" to p.action?.let { mapOf("type" to it.type, "value" to it.value) },
    )

    private fun surveyResponseToMap(r: SurveyResponse): Map<String, Any?> = mapOf(
        "questionId" to r.questionId,
        "answer" to r.answer,
        "metadata" to r.metadata,
    )

    // =========================================================================
    // SPEC-070-C Phase 2a — native -> Dart sync-callback invoker + reply decode.
    //
    // invokeDart() posts the MethodChannel invoke onto the main looper, awaits
    // the reply via suspendCancellableCoroutine, and wraps the whole thing in a
    // timeout. On timeout it logs a §5 diagnostic and returns null so the caller
    // substitutes the native default. A channel error / notImplemented also maps
    // to null (default). The Dart handler builds the reply maps whose shapes the
    // to*() decoders below match.
    // =========================================================================

    private suspend fun invokeDart(method: String, args: Map<String, Any?>): Any? {
        return try {
            withTimeout(syncCallbackTimeoutMs) {
                suspendCancellableCoroutine<Any?> { cont ->
                    mainHandler.post {
                        try {
                            syncCallbackChannel.invokeMethod(
                                method,
                                args,
                                object : MethodChannel.Result {
                                    override fun success(result: Any?) {
                                        if (cont.isActive) cont.resume(result)
                                    }
                                    override fun error(
                                        code: String,
                                        message: String?,
                                        details: Any?,
                                    ) {
                                        if (cont.isActive) cont.resume(null)
                                    }
                                    override fun notImplemented() {
                                        if (cont.isActive) cont.resume(null)
                                    }
                                },
                            )
                        } catch (t: Throwable) {
                            // Channel torn down mid-flight (engine detach) etc.
                            if (cont.isActive) cont.resume(null)
                        }
                    }
                }
            }
        } catch (e: TimeoutCancellationException) {
            Log.w("AppDNA", "sync_callbacks timeout: $method")
            null
        }
    }

    /** Coerce a decoded reply value into a `Map<String, Any>` (non-null values). */
    private fun asStringMap(v: Any?): Map<String, Any> {
        val m = v as? Map<*, *> ?: return emptyMap()
        val out = HashMap<String, Any>()
        for ((k, value) in m) {
            if (k is String && value != null) out[k] = value
        }
        return out
    }

    /**
     * `{type:"proceed"}` | `{type:"proceedWithData",data:{…}}` |
     * `{type:"block",message}` | `{type:"skipTo",stepId,data?}` |
     * `{type:"stay",message?}`  →  [StepAdvanceResult] (default Proceed).
     */
    private fun toStepAdvanceResult(reply: Any?): StepAdvanceResult {
        val map = reply as? Map<*, *> ?: return StepAdvanceResult.Proceed
        return when (map["type"] as? String ?: "proceed") {
            "proceedWithData" -> StepAdvanceResult.ProceedWithData(asStringMap(map["data"]))
            "block" -> StepAdvanceResult.Block(map["message"] as? String ?: "")
            "skipTo" -> StepAdvanceResult.SkipTo(
                map["stepId"] as? String ?: "",
                (map["data"] as? Map<*, *>)?.let { asStringMap(it) },
            )
            "stay" -> StepAdvanceResult.Stay(map["message"] as? String)
            else -> StepAdvanceResult.Proceed
        }
    }

    /** map-or-null → [StepConfigOverride]? (field-by-field; default null). */
    private fun toStepConfigOverride(reply: Any?): StepConfigOverride? {
        val map = reply as? Map<*, *> ?: return null
        return StepConfigOverride(
            fieldDefaults = (map["fieldDefaults"] as? Map<*, *>)?.let { asStringMap(it) },
            title = map["title"] as? String,
            subtitle = map["subtitle"] as? String,
            ctaText = map["ctaText"] as? String,
            layoutOverrides = (map["layoutOverrides"] as? Map<*, *>)?.let { asStringMap(it) },
        )
    }

    /** map-or-null → [ElementInteractionResult]? (default null). */
    private fun toElementInteractionResult(reply: Any?): ElementInteractionResult? {
        val map = reply as? Map<*, *> ?: return null
        val patches = (map["fieldConfigPatches"] as? Map<*, *>)?.let { raw ->
            val out = HashMap<String, Map<String, Any>>()
            for ((k, v) in raw) {
                if (k is String) out[k] = asStringMap(v)
            }
            out
        }
        return ElementInteractionResult(
            fieldConfigPatches = patches,
            inputValuePatches = (map["inputValuePatches"] as? Map<*, *>)?.let { asStringMap(it) },
            advance = map["advance"] as? Boolean ?: false,
        )
    }

    /**
     * map-or-null → [PermissionHandling]?. `{type:"handledByHost",granted}`
     * short-circuits the OS prompt; anything else → Proceed; null → null
     * (run the native flow).
     */
    private fun toPermissionHandling(reply: Any?): PermissionHandling? {
        val map = reply as? Map<*, *> ?: return null
        return when (map["type"] as? String ?: "proceed") {
            "handledByHost" -> PermissionHandling.HandledByHost(map["granted"] as? Boolean ?: false)
            else -> PermissionHandling.Proceed
        }
    }

    /** All 9 standard paywall lifecycle methods + post-purchase hooks. */
    private inner class PaywallDelegateForwarder : AppDNAPaywallDelegate {
        override fun onPaywallPresented(paywallId: String) {
            emit(paywallEventSink, "onPaywallPresented", mapOf("paywallId" to paywallId))
        }

        override fun onPaywallAction(paywallId: String, action: PaywallAction) {
            emit(
                paywallEventSink,
                "onPaywallAction",
                mapOf("paywallId" to paywallId, "action" to action.value),
            )
        }

        override fun onPaywallPurchaseStarted(paywallId: String, productId: String) {
            emit(
                paywallEventSink,
                "onPaywallPurchaseStarted",
                mapOf("paywallId" to paywallId, "productId" to productId),
            )
        }

        override fun onPaywallPurchaseCompleted(
            paywallId: String,
            productId: String,
            transaction: TransactionInfo,
        ) {
            emit(
                paywallEventSink,
                "onPaywallPurchaseCompleted",
                mapOf(
                    "paywallId" to paywallId,
                    "productId" to productId,
                    "transaction" to transactionToMap(transaction),
                ),
            )
        }

        override fun onPaywallPurchaseFailed(paywallId: String, error: Throwable) {
            emit(
                paywallEventSink,
                "onPaywallPurchaseFailed",
                mapOf("paywallId" to paywallId, "error" to throwableToMap(error)),
            )
        }

        override fun onPaywallRestoreStarted(paywallId: String) {
            emit(paywallEventSink, "onPaywallRestoreStarted", mapOf("paywallId" to paywallId))
        }

        override fun onPaywallRestoreCompleted(paywallId: String, productIds: List<String>) {
            emit(
                paywallEventSink,
                "onPaywallRestoreCompleted",
                mapOf("paywallId" to paywallId, "restoredProductIds" to productIds),
            )
        }

        override fun onPaywallRestoreFailed(paywallId: String, error: Throwable) {
            emit(
                paywallEventSink,
                "onPaywallRestoreFailed",
                mapOf("paywallId" to paywallId, "error" to throwableToMap(error)),
            )
        }

        override fun onPaywallDismissed(paywallId: String) {
            emit(paywallEventSink, "onPaywallDismissed", mapOf("paywallId" to paywallId))
        }

        override fun onPostPurchaseDeepLink(paywallId: String, url: String) {
            emit(
                paywallEventSink,
                "onPostPurchaseDeepLink",
                mapOf("paywallId" to paywallId, "url" to url),
            )
        }

        override fun onPostPurchaseNextStep(paywallId: String) {
            emit(paywallEventSink, "onPostPurchaseNextStep", mapOf("paywallId" to paywallId))
        }

        // onPromoCodeSubmit is NOT forwarded: it's a synchronous validation
        // callback (host must invoke the completion handler with true/false
        // before the Activity advances). Bridging that across the event-channel
        // boundary requires a CompletableDeferred handshake — left to a
        // follow-up. Default impl already returns false (= reject promo),
        // matching the iOS observe-only event-channel contract for v1.
    }

    /** Onboarding observe-only callbacks (4 methods). */
    private inner class OnboardingDelegateForwarder : AppDNAOnboardingDelegate {
        override fun onOnboardingStarted(flowId: String) {
            emit(onboardingEventSink, "onOnboardingStarted", mapOf("flowId" to flowId))
        }

        override fun onOnboardingStepChanged(
            flowId: String,
            stepId: String,
            stepIndex: Int,
            totalSteps: Int,
        ) {
            emit(
                onboardingEventSink,
                "onOnboardingStepChanged",
                mapOf(
                    "flowId" to flowId,
                    "stepId" to stepId,
                    "stepIndex" to stepIndex,
                    "totalSteps" to totalSteps,
                ),
            )
        }

        override fun onOnboardingCompleted(flowId: String, responses: Map<String, Any>) {
            emit(
                onboardingEventSink,
                "onOnboardingCompleted",
                mapOf("flowId" to flowId, "responses" to responses),
            )
        }

        override fun onOnboardingDismissed(flowId: String, atStep: Int) {
            emit(
                onboardingEventSink,
                "onOnboardingDismissed",
                mapOf("flowId" to flowId, "atStep" to atStep),
            )
        }

        // SPEC-070-C Phase 2a — async return-value hooks. Each invokes the Dart
        // host over the sync_callbacks channel, awaits the reply map, converts
        // it to the native return DTO, and falls back to the SDK default on
        // null/timeout. The invoker + to*() decoders live on the outer plugin.

        override suspend fun onBeforeStepAdvance(
            flowId: String,
            fromStepId: String,
            stepIndex: Int,
            stepType: String,
            responses: Map<String, Any>,
            stepData: Map<String, Any>?,
        ): StepAdvanceResult {
            val args = mutableMapOf<String, Any?>(
                "flowId" to flowId,
                "fromStepId" to fromStepId,
                "stepIndex" to stepIndex,
                "stepType" to stepType,
                "responses" to responses,
            )
            if (stepData != null) args["stepData"] = stepData
            return toStepAdvanceResult(invokeDart("onBeforeStepAdvance", args))
        }

        override suspend fun onBeforeStepRender(
            flowId: String,
            stepId: String,
            stepIndex: Int,
            stepType: String,
            responses: Map<String, Any>,
        ): StepConfigOverride? {
            return toStepConfigOverride(
                invokeDart(
                    "onBeforeStepRender",
                    mapOf(
                        "flowId" to flowId,
                        "stepId" to stepId,
                        "stepIndex" to stepIndex,
                        "stepType" to stepType,
                        "responses" to responses,
                    ),
                ),
            )
        }

        override suspend fun onElementInteraction(
            flowId: String,
            stepId: String,
            blockId: String,
            action: String,
            value: String?,
            inputValues: Map<String, Any>,
        ): ElementInteractionResult? {
            val args = mutableMapOf<String, Any?>(
                "flowId" to flowId,
                "stepId" to stepId,
                "blockId" to blockId,
                "action" to action,
                "inputValues" to inputValues,
            )
            if (value != null) args["value"] = value
            return toElementInteractionResult(invokeDart("onElementInteraction", args))
        }

        override suspend fun onPermissionRequest(permissionType: String): PermissionHandling? {
            return toPermissionHandling(
                invokeDart("onPermissionRequest", mapOf("permissionType" to permissionType)),
            )
        }
    }

    /** Survey lifecycle (3 methods). */
    private inner class SurveyDelegateForwarder : AppDNASurveyDelegate {
        override fun onSurveyPresented(surveyId: String) {
            emit(surveyEventSink, "onSurveyPresented", mapOf("surveyId" to surveyId))
        }

        override fun onSurveyCompleted(surveyId: String, responses: List<SurveyResponse>) {
            emit(
                surveyEventSink,
                "onSurveyCompleted",
                mapOf("surveyId" to surveyId, "responses" to responses.map { surveyResponseToMap(it) }),
            )
        }

        override fun onSurveyDismissed(surveyId: String) {
            emit(surveyEventSink, "onSurveyDismissed", mapOf("surveyId" to surveyId))
        }
    }

    /** In-app message lifecycle (3 observe + 1 veto). */
    private inner class InAppMessageDelegateForwarder : AppDNAInAppMessageDelegate {
        override fun onMessageShown(messageId: String, trigger: String) {
            emit(
                inAppMessageEventSink,
                "onMessageShown",
                mapOf("messageId" to messageId, "trigger" to trigger),
            )
        }

        override fun onMessageAction(messageId: String, action: String, data: Map<String, Any>?) {
            emit(
                inAppMessageEventSink,
                "onMessageAction",
                mapOf("messageId" to messageId, "action" to action, "data" to data),
            )
        }

        override fun onMessageDismissed(messageId: String) {
            emit(inAppMessageEventSink, "onMessageDismissed", mapOf("messageId" to messageId))
        }

        /**
         * Veto hook. v1 ALWAYS returns `true` — see plugin contract note.
         * The callback still surfaces through the event channel as an
         * observe-only `shouldShowMessage` event so Dart code can log /
         * record the call, but cannot actually block display. Real veto
         * support requires bridging this sync return through Dart via the
         * `com.appdna.sdk/sync_callbacks` MethodChannel with a
         * CompletableDeferred / timeout handshake — left to a follow-up.
         */
        override fun shouldShowMessage(messageId: String): Boolean {
            emit(inAppMessageEventSink, "shouldShowMessage", mapOf("messageId" to messageId))
            return true
        }
    }

    /** Push notification lifecycle (3 methods). */
    private inner class PushDelegateForwarder : AppDNAPushDelegate {
        override fun onPushTokenRegistered(token: String) {
            emit(pushEventSink, "onPushTokenRegistered", mapOf("token" to token))
        }

        override fun onPushReceived(notification: PushPayload, inForeground: Boolean) {
            emit(
                pushEventSink,
                "onPushReceived",
                mapOf(
                    "notification" to pushPayloadToMap(notification),
                    "inForeground" to inForeground,
                ),
            )
        }

        override fun onPushTapped(notification: PushPayload, actionId: String?) {
            emit(
                pushEventSink,
                "onPushTapped",
                mapOf(
                    "notification" to pushPayloadToMap(notification),
                    "actionId" to actionId,
                ),
            )
        }
    }

    /** Billing observer (5 methods incl. onBillingUnavailable). */
    private inner class BillingDelegateForwarder : AppDNABillingDelegate {
        override fun onPurchaseCompleted(productId: String, transaction: TransactionInfo) {
            emit(
                billingDelegateEventSink,
                "onPurchaseCompleted",
                mapOf("productId" to productId, "transaction" to transactionToMap(transaction)),
            )
        }

        override fun onPurchaseFailed(productId: String, error: Throwable) {
            emit(
                billingDelegateEventSink,
                "onPurchaseFailed",
                mapOf("productId" to productId, "error" to throwableToMap(error)),
            )
        }

        override fun onEntitlementsChanged(entitlements: List<Entitlement>) {
            emit(
                billingDelegateEventSink,
                "onEntitlementsChanged",
                mapOf("entitlements" to entitlements.map { entitlementToMap(it) }),
            )
        }

        override fun onRestoreCompleted(restoredProducts: List<String>) {
            emit(
                billingDelegateEventSink,
                "onRestoreCompleted",
                mapOf("restoredProductIds" to restoredProducts),
            )
        }

        override fun onBillingUnavailable() {
            emit(billingDelegateEventSink, "onBillingUnavailable", emptyMap())
        }
    }

    /** Deep link receiver (1 method on the native interface). */
    private inner class DeepLinkDelegateForwarder : AppDNADeepLinkDelegate {
        override fun onDeepLinkReceived(url: String, params: Map<String, String>) {
            emit(
                deepLinkEventSink,
                "onDeepLinkReceived",
                mapOf("url" to url, "params" to params),
            )
        }
    }

    /** Server-driven screen lifecycle (3 observe + 1 veto). */
    private inner class ScreenDelegateForwarder : AppDNAScreenDelegate {
        override fun onScreenPresented(screenId: String) {
            emit(screenEventSink, "onScreenPresented", mapOf("screenId" to screenId))
        }

        override fun onScreenDismissed(screenId: String, result: Map<String, Any?>) {
            emit(
                screenEventSink,
                "onScreenDismissed",
                mapOf("screenId" to screenId, "result" to result),
            )
        }

        override fun onFlowCompleted(flowId: String, result: Map<String, Any?>) {
            emit(
                screenEventSink,
                "onFlowCompleted",
                mapOf("flowId" to flowId, "result" to result),
            )
        }

        /**
         * Veto hook. Like in-app messages, v1 ALWAYS returns `true` and
         * surfaces the action via the screen event channel as observe-only.
         * Dart can record the action and emit analytics but cannot block
         * default SDK handling. Real veto requires the sync_callbacks
         * MethodChannel handshake (follow-up).
         */
        override fun onScreenAction(screenId: String, action: Map<String, Any?>): Boolean {
            emit(
                screenEventSink,
                "onScreenAction",
                mapOf("screenId" to screenId, "action" to action),
            )
            return true
        }
    }
}
