package com.appdna.flutter

import android.app.Activity
import android.content.Context
import ai.appdna.sdk.AppDNA
import ai.appdna.sdk.AppDNAOptions
import ai.appdna.sdk.Environment
import ai.appdna.sdk.LogLevel
import ai.appdna.sdk.paywalls.PaywallContext
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*

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
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        billingChannel.setMethodCallHandler(null)
        entitlementEventChannel.setStreamHandler(null)
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
                scope.launch {
                    try {
                        val purchaseResult = AppDNA.billing.purchase(productId, offerToken)
                        result.success(purchaseResult.toMap())
                    } catch (e: Exception) {
                        result.error("PURCHASE_ERROR", e.message, null)
                    }
                }
            }
            "restorePurchases" -> {
                scope.launch {
                    try {
                        val entitlements = AppDNA.billing.restorePurchases()
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
}
