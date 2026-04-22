package net.linksense.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
// Native SDK import. Pre-release, the `net.linksense:sdk` dependency
// is commented out in build.gradle — when wired, this import compiles
// against the module published from `/linksense-android`.
import net.linksense.sdk.LinkSense
import net.linksense.sdk.LinkSenseConfiguration
import net.linksense.sdk.LinkSenseError
import net.linksense.sdk.LogLevel as SdkLogLevel
import net.linksense.sdk.links.CreateLinkOptions
import net.linksense.sdk.links.FieldUpdate
import net.linksense.sdk.links.Link
import net.linksense.sdk.links.LinkMetadataValue
import net.linksense.sdk.links.UpdateLinkOptions

/**
 * Flutter→Android bridge. Routes MethodChannel calls to the LinkSense
 * Kotlin facade and forwards deferred-deep-link events over an
 * EventChannel. Method names match the Dart facade exactly.
 *
 * Implements [ActivityAware] so we can forward `Activity#onNewIntent`
 * App-Link launches into [LinkSense.handleIntent] without the
 * integrator writing any boilerplate in the host Activity.
 */
class LinksensePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var activityBinding: ActivityPluginBinding? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var eventSink: EventChannel.EventSink? = null
    private var bufferedDeepLink: String? = null
    private var bufferedReady: Boolean = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "net.linksense.flutter/method")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "net.linksense.flutter/deep-links")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // MARK: - MethodCallHandler

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> handleConfigure(call, result)
            "start" -> handleStart(result)
            "createLink" -> handleCreateLink(call, result)
            "getLink" -> handleGetLink(call, result)
            "updateLink" -> handleUpdateLink(call, result)
            "deleteLink" -> handleDeleteLink(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleConfigure(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: run {
            result.error("INVALID_INPUT", "configure requires a map argument", null)
            return
        }
        val sdkKey = args["sdk_key"] as? String ?: run {
            result.error("INVALID_INPUT", "configure requires sdk_key", null)
            return
        }
        val baseUrl = args["base_url"] as? String
        val enableInstallReferrer = args["enable_install_referrer"] as? Boolean ?: true
        val enableFingerprint = args["enable_fingerprint"] as? Boolean ?: true
        val logLevelName = (args["log_level"] as? String) ?: "off"
        val logLevel = when (logLevelName) {
            "error" -> SdkLogLevel.ERROR
            "info" -> SdkLogLevel.INFO
            "debug" -> SdkLogLevel.DEBUG
            else -> SdkLogLevel.OFF
        }
        LinkSense.configure(
            applicationContext,
            LinkSenseConfiguration(
                sdkKey = sdkKey,
                baseUrl = baseUrl,
                enableInstallReferrer = enableInstallReferrer,
                enableFingerprint = enableFingerprint,
                logLevel = logLevel,
            ),
        )
        result.success(null)
    }

    private fun handleStart(result: MethodChannel.Result) {
        LinkSense.onDeferredDeepLink { uri ->
            val encoded = uri?.toString() ?: ""
            val sink = eventSink
            if (sink != null) {
                sink.success(encoded)
            } else {
                bufferedDeepLink = encoded
                bufferedReady = true
            }
        }
        LinkSense.start()
        result.success(null)
    }

    private fun handleCreateLink(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: run {
            result.error("INVALID_INPUT", "createLink requires options map", null)
            return
        }
        val options = createOptionsFrom(args) ?: run {
            result.error("INVALID_INPUT", "createLink requires name", null)
            return
        }
        scope.launch {
            try {
                val link = LinkSense.createLink(options)
                result.success(encodeLink(link))
            } catch (error: Throwable) {
                surfaceError(result, error)
            }
        }
    }

    private fun handleGetLink(call: MethodCall, result: MethodChannel.Result) {
        val id = (call.arguments as? Map<*, *>)?.get("id") as? String ?: run {
            result.error("INVALID_INPUT", "getLink requires id", null)
            return
        }
        scope.launch {
            try {
                val link = LinkSense.getLink(id)
                result.success(encodeLink(link))
            } catch (error: Throwable) {
                surfaceError(result, error)
            }
        }
    }

    private fun handleUpdateLink(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.arguments as? Map<*, *>
        val id = raw?.get("id") as? String
        val options = raw?.get("options") as? Map<*, *>
        if (id == null || options == null) {
            result.error("INVALID_INPUT", "updateLink requires id and options", null)
            return
        }
        scope.launch {
            try {
                val link = LinkSense.updateLink(id, updateOptionsFrom(options))
                result.success(encodeLink(link))
            } catch (error: Throwable) {
                surfaceError(result, error)
            }
        }
    }

    private fun handleDeleteLink(call: MethodCall, result: MethodChannel.Result) {
        val id = (call.arguments as? Map<*, *>)?.get("id") as? String ?: run {
            result.error("INVALID_INPUT", "deleteLink requires id", null)
            return
        }
        scope.launch {
            try {
                LinkSense.deleteLink(id)
                result.success(null)
            } catch (error: Throwable) {
                surfaceError(result, error)
            }
        }
    }

    // MARK: - EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (bufferedReady) {
            events?.success(bufferedDeepLink ?: "")
            bufferedDeepLink = null
            bufferedReady = false
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - ActivityAware + NewIntentListener (App-Link forwarding)

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        forwardIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        return forwardIntent(intent)
    }

    private fun forwardIntent(intent: Intent?): Boolean {
        return LinkSense.handleIntent(intent) { uri ->
            val encoded = uri?.toString() ?: ""
            val sink = eventSink
            if (sink != null) {
                sink.success(encoded)
            } else {
                bufferedDeepLink = encoded
                bufferedReady = true
            }
        }
    }

    // MARK: - Helpers

    private fun createOptionsFrom(map: Map<*, *>): CreateLinkOptions? {
        val name = map["name"] as? String ?: return null
        return CreateLinkOptions(
            name = name,
            desktopUrl = map["desktop_url"] as? String,
            slug = map["slug"] as? String,
            tags = (map["tags"] as? List<*>)?.mapNotNull { it as? String },
            metadata = (map["metadata"] as? Map<*, *>)?.let(::toMetadataMap),
            iosClipboardEnabled = map["ios_clipboard_enabled"] as? Boolean,
            iosFallbackUrl = map["ios_fallback_url"] as? String,
            androidFallbackUrl = map["android_fallback_url"] as? String,
            ogTitle = map["og_title"] as? String,
            ogDescription = map["og_description"] as? String,
            ogImageUrl = map["og_image_url"] as? String,
        )
    }

    private fun updateOptionsFrom(map: Map<*, *>): UpdateLinkOptions {
        return UpdateLinkOptions(
            name = (map["name"] as? String)?.let(FieldUpdate::Set) ?: FieldUpdate.Absent,
            desktopUrl = fieldUpdate(map, "desktop_url") { it as? String },
            tags = (map["tags"] as? List<*>)?.let { tags -> FieldUpdate.Set(tags.mapNotNull { it as? String }) }
                ?: FieldUpdate.Absent,
            metadata = fieldUpdate(map, "metadata") { value ->
                if (value == null) null else toMetadataMap(value as Map<*, *>)
            },
            iosClipboardEnabled = (map["ios_clipboard_enabled"] as? Boolean)?.let(FieldUpdate::Set) ?: FieldUpdate.Absent,
            iosFallbackUrl = fieldUpdate(map, "ios_fallback_url") { it as? String },
            androidFallbackUrl = fieldUpdate(map, "android_fallback_url") { it as? String },
            ogTitle = fieldUpdate(map, "og_title") { it as? String },
            ogDescription = fieldUpdate(map, "og_description") { it as? String },
            ogImageUrl = fieldUpdate(map, "og_image_url") { it as? String },
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> fieldUpdate(map: Map<*, *>, key: String, transform: (Any?) -> T?): FieldUpdate<T?> {
        if (!map.containsKey(key)) return FieldUpdate.Absent
        val raw = map[key]
        return if (raw == null) FieldUpdate.Clear else FieldUpdate.Set(transform(raw))
    }

    private fun toMetadataMap(raw: Map<*, *>): Map<String, LinkMetadataValue> {
        val result = mutableMapOf<String, LinkMetadataValue>()
        for ((key, value) in raw) {
            val k = key as? String ?: continue
            val v = toMetadataValue(value) ?: continue
            result[k] = v
        }
        return result
    }

    private fun toMetadataValue(value: Any?): LinkMetadataValue? = when (value) {
        null -> LinkMetadataValue.Null
        is String -> LinkMetadataValue.StringValue(value)
        is Boolean -> LinkMetadataValue.BoolValue(value)
        is Int -> LinkMetadataValue.LongValue(value.toLong())
        is Long -> LinkMetadataValue.LongValue(value)
        is Double -> LinkMetadataValue.DoubleValue(value)
        is Float -> LinkMetadataValue.DoubleValue(value.toDouble())
        is List<*> -> LinkMetadataValue.ArrayValue(value.mapNotNull { toMetadataValue(it) })
        is Map<*, *> -> LinkMetadataValue.ObjectValue(toMetadataMap(value))
        else -> null
    }

    private fun encodeLink(link: Link): Map<String, Any?> = mapOf(
        "id" to link.id,
        "project_id" to link.projectId,
        "name" to link.name,
        "custom_path" to link.slug,
        "full_url" to link.fullUrl,
        "desktop_url" to link.desktopUrl,
        "ios_fallback_url" to link.iosFallbackUrl,
        "android_fallback_url" to link.androidFallbackUrl,
        "og_title" to link.ogTitle,
        "og_description" to link.ogDescription,
        "og_image_url" to link.ogImageUrl,
        "tags" to link.tags,
        "ios_clipboard_enabled" to link.iosClipboardEnabled,
        "created_at" to link.createdAt,
        "updated_at" to link.updatedAt,
    )

    private fun surfaceError(result: MethodChannel.Result, error: Throwable) {
        when (error) {
            is LinkSenseError.NotConfigured -> result.error("NOT_CONFIGURED", error.message, null)
            is LinkSenseError.InvalidSdkKey -> result.error("INVALID_SDK_KEY", error.message, null)
            is LinkSenseError.Network -> result.error("NETWORK", error.message, null)
            is LinkSenseError.Server -> result.error(error.code, error.serverMessage, mapOf("status" to error.status))
            is LinkSenseError.DecodeFailure -> result.error("DECODE_FAILURE", error.message, null)
            is LinkSenseError.ForbiddenCrossScope -> result.error("FORBIDDEN_CROSS_SCOPE", error.message, null)
            is LinkSenseError.ForbiddenField -> result.error("FORBIDDEN_FIELD", error.message, null)
            is LinkSenseError.RateLimited -> result.error(
                "RATE_LIMITED",
                error.message,
                mapOf("retryAfter" to error.retryAfterSeconds),
            )
            else -> result.error("UNKNOWN", error.message ?: "unknown", null)
        }
    }
}
