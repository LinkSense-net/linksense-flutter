import Flutter
import UIKit
// The LinkSense iOS SDK is vendored into this module (LinkSenseCore/, synced
// by ios/sync-ios-sdk.sh), so its types need no import.

/// Flutter→iOS bridge. Routes MethodChannel calls to `LinkSense.shared` and
/// emits Universal Link opens on `…/deep-links` and the deferred `start()`
/// result on `…/deferred-deep-links`.
///
/// Method names match the Dart facade in `lib/linksense.dart`. Every error
/// surfaced to Flutter is a `FlutterError` whose `code` matches the codes in
/// `lib/src/exceptions.dart`.
public class SwiftLinksensePlugin: NSObject, FlutterPlugin {

    /// Link opens (Universal Links).
    private let deepLinks = BufferedStream()
    /// The deferred deep link from `start()`.
    private let deferredDeepLinks = BufferedStream()
    private var isConfigured = false
    /// Universal Links that arrived before `configure` (a cold launch from a
    /// link reaches the app delegate before Dart has run).
    private var pendingActivities: [NSUserActivity] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "net.linksense.flutter/method",
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftLinksensePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        registrar.addApplicationDelegate(instance)
        FlutterEventChannel(name: "net.linksense.flutter/deep-links", binaryMessenger: registrar.messenger())
            .setStreamHandler(instance.deepLinks)
        FlutterEventChannel(name: "net.linksense.flutter/deferred-deep-links", binaryMessenger: registrar.messenger())
            .setStreamHandler(instance.deferredDeepLinks)
    }

    // MARK: - App delegate (Universal Links)

    /// Observes every Universal Link so the integrator never edits
    /// AppDelegate. Returns `false`: LinkSense reports the open and resolves
    /// first-launch attribution, while routing stays with the app's router.
    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([Any]) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, userActivity.webpageURL != nil else {
            return false
        }
        if isConfigured {
            forward(userActivity)
        } else {
            pendingActivities.append(userActivity)
        }
        return false
    }

    private func forward(_ activity: NSUserActivity) {
        LinkSense.shared.continueUserActivity(activity) { [weak self] resolved in
            self?.deepLinks.emit(resolved)
        }
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            handleConfigure(call, result: result)
        case "start":
            LinkSense.shared.onDeferredDeepLink { [weak self] url in self?.deferredDeepLinks.emit(url) }
            LinkSense.shared.start()
            result(nil)
        case "submitPastedLink":
            guard let args = call.arguments as? [String: Any], let text = args["text"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "submitPastedLink requires text", details: nil))
                return
            }
            LinkSense.shared.submitPastedLink(text) { url in result(url?.absoluteString) }
        case "createLink", "getLink", "updateLink", "deleteLink":
            handleLinkOp(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleConfigure(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let sdkKey = args["sdk_key"] as? String else {
            result(FlutterError(code: "INVALID_INPUT", message: "configure requires sdk_key", details: nil))
            return
        }
        let logLevel: LogLevel
        switch (args["log_level"] as? String) ?? "off" {
        case "error": logLevel = .error
        case "info": logLevel = .info
        case "debug": logLevel = .debug
        default: logLevel = .off
        }
        do {
            try LinkSense.shared.configure(LinkSenseConfiguration(
                sdkKey: sdkKey,
                enableClipboard: args["enable_clipboard"] as? Bool ?? false,
                logLevel: logLevel
            ))
        } catch let error as LinkSenseError {
            result(SwiftLinksensePlugin.flutterError(from: error))
            return
        } catch {
            result(FlutterError(code: "INVALID_SDK_KEY", message: error.localizedDescription, details: nil))
            return
        }
        isConfigured = true
        let queued = pendingActivities
        pendingActivities.removeAll()
        queued.forEach(forward)
        result(nil)
    }

    // MARK: - Link CRUD

    private func handleLinkOp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "createLink":
            guard let options = SwiftLinksensePlugin.createOptions(from: call.arguments) else {
                result(FlutterError(code: "INVALID_INPUT", message: "createLink requires options map", details: nil))
                return
            }
            LinkSense.shared.createLink(options: options) { SwiftLinksensePlugin.resolveLink($0, result: result) }

        case "getLink":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "getLink requires id", details: nil))
                return
            }
            LinkSense.shared.getLink(id: id) { SwiftLinksensePlugin.resolveLink($0, result: result) }

        case "updateLink":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "updateLink requires id", details: nil))
                return
            }
            let options = SwiftLinksensePlugin.updateOptions(from: (args?["options"] as? [String: Any]) ?? [:])
            LinkSense.shared.updateLink(id, options: options) { SwiftLinksensePlugin.resolveLink($0, result: result) }

        case "deleteLink":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "deleteLink requires id", details: nil))
                return
            }
            LinkSense.shared.deleteLink(id) { outcome in
                switch outcome {
                case .success: result(nil)
                case .failure(let error): result(SwiftLinksensePlugin.flutterError(from: error))
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func url(_ value: Any?) -> URL? {
        (value as? String).flatMap(URL.init(string:))
    }

    private static func createOptions(from raw: Any?) -> CreateLinkOptions? {
        guard let map = raw as? [String: Any], let name = map["name"] as? String else { return nil }
        return CreateLinkOptions(
            name: name,
            desktopUrl: url(map["desktop_url"]),
            slug: map["slug"] as? String,
            tags: map["tags"] as? [String],
            metadata: (map["metadata"] as? [String: Any]).map(toLinkMetadataMap),
            iosClipboardEnabled: map["ios_clipboard_enabled"] as? Bool,
            iosFallbackUrl: url(map["ios_fallback_url"]),
            androidFallbackUrl: url(map["android_fallback_url"]),
            ogTitle: map["og_title"] as? String,
            ogDescription: map["og_description"] as? String,
            ogImageUrl: url(map["og_image_url"])
        )
    }

    /// Dart sends a key with `null` to clear a field and omits it to leave it.
    private static func updateOptions(from map: [String: Any]) -> UpdateLinkOptions {
        func optional<T>(_ key: String, _ convert: (Any?) -> T?) -> FieldUpdate<T> {
            guard map.keys.contains(key) else { return .unchanged }
            if let value = convert(map[key]) { return .set(value) }
            return .clear
        }
        func required<T>(_ key: String) -> RequiredFieldUpdate<T> {
            (map[key] as? T).map { .set($0) } ?? .unchanged
        }
        return UpdateLinkOptions(
            name: required("name"),
            desktopUrl: optional("desktop_url", url),
            tags: required("tags"),
            metadata: optional("metadata") { ($0 as? [String: Any]).map(toLinkMetadataMap) },
            iosClipboardEnabled: required("ios_clipboard_enabled"),
            iosFallbackUrl: optional("ios_fallback_url", url),
            androidFallbackUrl: optional("android_fallback_url", url),
            ogTitle: optional("og_title") { $0 as? String },
            ogDescription: optional("og_description") { $0 as? String },
            ogImageUrl: optional("og_image_url", url)
        )
    }

    private static func toLinkMetadataMap(_ raw: [String: Any]) -> [String: LinkMetadataValue] {
        raw.compactMapValues(toLinkMetadataValue)
    }

    private static func toLinkMetadataValue(_ value: Any) -> LinkMetadataValue? {
        switch value {
        case let s as String: return .string(s)
        // Flutter hands bools and numbers over as NSNumber; check the
        // CF type so a 1 isn't read as `true` (or `true` as 1).
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) { return .double(n.doubleValue) }
            return .int(n.intValue)
        case let arr as [Any]: return .array(arr.compactMap(toLinkMetadataValue))
        case let map as [String: Any]: return .object(map.compactMapValues(toLinkMetadataValue))
        case is NSNull: return .null
        default: return nil
        }
    }

    private static func resolveLink(_ outcome: Result<Link, LinkSenseError>, result: @escaping FlutterResult) {
        switch outcome {
        case .success(let link): result(encodeLink(link))
        case .failure(let error): result(flutterError(from: error))
        }
    }

    private static func encodeLink(_ link: Link) -> [String: Any?] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [
            "id": link.id,
            "project_id": link.projectId,
            "name": link.name,
            "custom_path": link.slug,
            "full_url": link.fullUrl.absoluteString,
            "desktop_url": link.desktopUrl?.absoluteString,
            "ios_fallback_url": link.iosFallbackUrl?.absoluteString,
            "android_fallback_url": link.androidFallbackUrl?.absoluteString,
            "og_title": link.ogTitle,
            "og_description": link.ogDescription,
            "og_image_url": link.ogImageUrl?.absoluteString,
            "tags": link.tags,
            "ios_clipboard_enabled": link.iosClipboardEnabled,
            "metadata": link.metadata.map { $0.mapValues(encodeMetadata) },
            "created_at": iso.string(from: link.createdAt),
            "updated_at": iso.string(from: link.updatedAt),
        ]
    }

    /// Plain channel-codec values; `NSNull` keeps a JSON null inside
    /// containers (Swift `nil` can't live in `[Any]`).
    private static func encodeMetadata(_ value: LinkMetadataValue) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map(encodeMetadata)
        case .object(let o): return o.mapValues(encodeMetadata)
        case .null: return NSNull()
        }
    }

    private static func flutterError(from error: LinkSenseError) -> FlutterError {
        let message = error.localizedDescription
        switch error {
        case .notConfigured: return FlutterError(code: "NOT_CONFIGURED", message: message, details: nil)
        case .invalidSdkKey: return FlutterError(code: "INVALID_SDK_KEY", message: message, details: nil)
        case .network: return FlutterError(code: "NETWORK", message: message, details: nil)
        case .server(let code, _, let status): return FlutterError(code: code, message: message, details: ["status": status])
        case .decodeFailure: return FlutterError(code: "DECODE_FAILURE", message: message, details: nil)
        case .forbiddenCrossScope: return FlutterError(code: "FORBIDDEN_CROSS_SCOPE", message: message, details: nil)
        case .forbiddenField: return FlutterError(code: "FORBIDDEN_FIELD", message: message, details: nil)
        case .rateLimited(let retryAfterSeconds):
            return FlutterError(code: "RATE_LIMITED", message: message, details: ["retryAfterSeconds": retryAfterSeconds as Any])
        case .unauthorized: return FlutterError(code: "UNAUTHORIZED", message: message, details: nil)
        case .notFound: return FlutterError(code: "NOT_FOUND", message: message, details: nil)
        case .slugExists: return FlutterError(code: "SLUG_EXISTS", message: message, details: nil)
        case .accessDenied(let d):
            return FlutterError(code: "ACCESS_DENIED", message: d.serverMessage, details: [
                "upgradeRequired": d.upgradeRequired,
                "plan": d.plan as Any,
                "currentUsage": d.currentUsage as Any,
                "limit": d.limit as Any,
            ])
        case .invalidInput(let fieldErrors):
            return FlutterError(code: "INVALID_INPUT", message: message, details: ["fieldErrors": fieldErrors])
        }
    }
}

/// One EventChannel's sink plus a FIFO buffer of events that arrived while
/// no Dart listener was attached; the buffer is flushed on listen.
private final class BufferedStream: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private var buffer: [String] = []

    /// `""` stands for an unresolved (nil) link.
    func emit(_ url: URL?) {
        let encoded = url?.absoluteString ?? ""
        DispatchQueue.main.async {
            if let sink = self.sink { sink(encoded) } else { self.buffer.append(encoded) }
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        buffer.forEach { events($0) }
        buffer.removeAll()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
