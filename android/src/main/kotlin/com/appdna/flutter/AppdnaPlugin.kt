package com.appdna.flutter

import android.app.Activity
import android.content.Context
import ai.appdna.sdk.AppDNA
import ai.appdna.sdk.Environment
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class AppdnaPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.appdna.sdk/main")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "com.appdna.sdk/web_entitlement")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> {
                val apiKey = call.argument<String>("apiKey")!!
                val envStr = call.argument<String>("env") ?: "production"
                val env = if (envStr == "staging") Environment.SANDBOX else Environment.PRODUCTION
                context?.let { AppDNA.configure(it, apiKey, env) }
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
                activity?.let { AppDNA.presentPaywall(it, id) }
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
            else -> result.notImplemented()
        }
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
