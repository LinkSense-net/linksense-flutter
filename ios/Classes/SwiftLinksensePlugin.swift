import Flutter
import UIKit
// Native SDK import. Pre-release: the dependency is commented out in
// `linksense.podspec` until the SDK pod is published — the bridge is
// written to compile against the Swift module from the sibling repo.
#if canImport(LinkSense)
import LinkSense
#endif

/// Flutter→iOS bridge. Routes MethodChannel calls to `LinkSense.shared`
/// and forwards the deferred deep link over an EventChannel.
///
/// Method names match the Dart facade in `lib/linksense.dart` (see
/// `invokeAndTranslate` call sites). Every error surfaced to Flutter
/// uses `FlutterError` whose `code` matches the server / SDK error
/// codes documented in `lib/src/exceptions.dart`.
public class SwiftLinksensePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    private var bufferedDeepLink: String?
    private var bufferedReady: Bool = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "net.linksense.flutter/method",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "net.linksense.flutter/deep-links",
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftLinksensePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            handleConfigure(call, result: result)
        case "start":
            handleStart(result: result)
        case "createLink", "getLink", "updateLink", "deleteLink":
            handleLinkOp(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleConfigure(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        #if canImport(LinkSense)
        guard let args = call.arguments as? [String: Any], let sdkKey = args["sdk_key"] as? String else {
            result(FlutterError(code: "INVALID_INPUT", message: "configure requires sdk_key", details: nil))
            return
        }
        let baseURLString = args["base_url"] as? String
        let baseURL = baseURLString.flatMap(URL.init(string:))
        let enableClipboard = args["enable_clipboard"] as? Bool ?? false
        let logLevelName = (args["log_level"] as? String) ?? "off"
        let logLevel: LogLevel = {
            switch logLevelName {
            case "error": return .error
            case "info": return .info
            case "debug": return .debug
            default: return .off
            }
        }()

        let config = LinkSenseConfiguration(
            sdkKey: sdkKey,
            baseURL: baseURL,
            enableClipboard: enableClipboard,
            logLevel: logLevel
        )
        LinkSense.shared.configure(config)
        result(nil)
        #else
        result(FlutterError(code: "NOT_CONFIGURED", message: "Native LinkSense SDK missing", details: nil))
        #endif
    }

    private func handleStart(result: @escaping FlutterResult) {
        #if canImport(LinkSense)
        LinkSense.shared.onDeferredDeepLink { [weak self] url in
            guard let self = self else { return }
            let encoded = url?.absoluteString
            if let sink = self.eventSink {
                sink(encoded ?? "")
            } else {
                self.bufferedDeepLink = encoded
                self.bufferedReady = true
            }
        }
        LinkSense.shared.start()
        result(nil)
        #else
        result(FlutterError(code: "NOT_CONFIGURED", message: "Native LinkSense SDK missing", details: nil))
        #endif
    }

    private func handleLinkOp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        #if canImport(LinkSense)
        switch call.method {
        case "createLink":
            guard let options = SwiftLinksensePlugin.createOptions(from: call.arguments) else {
                result(FlutterError(code: "INVALID_INPUT", message: "createLink requires options map", details: nil))
                return
            }
            LinkSense.shared.createLink(options: options) { outcome in
                SwiftLinksensePlugin.resolveLink(outcome, result: result)
            }

        case "getLink":
            guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "getLink requires id", details: nil))
                return
            }
            LinkSense.shared.link(withId: id) { outcome in
                SwiftLinksensePlugin.resolveLink(outcome, result: result)
            }

        case "updateLink":
            guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "updateLink requires id", details: nil))
                return
            }
            let optionsRaw = (args["options"] as? [String: Any]) ?? [:]
            let options = SwiftLinksensePlugin.updateOptions(from: optionsRaw)
            LinkSense.shared.updateLink(id, options: options) { outcome in
                SwiftLinksensePlugin.resolveLink(outcome, result: result)
            }

        case "deleteLink":
            guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
                result(FlutterError(code: "INVALID_INPUT", message: "deleteLink requires id", details: nil))
                return
            }
            LinkSense.shared.deleteLink(id) { outcome in
                switch outcome {
                case .success:
                    result(nil)
                case .failure(let error):
                    result(SwiftLinksensePlugin.flutterError(from: error))
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
        #else
        result(FlutterError(code: "NOT_CONFIGURED", message: "Native LinkSense SDK missing", details: nil))
        #endif
    }

    #if canImport(LinkSense)
    private static func createOptions(from raw: Any?) -> CreateLinkOptions? {
        guard let map = raw as? [String: Any], let name = map["name"] as? String else { return nil }
        return CreateLinkOptions(
            name: name,
            desktopUrl: (map["desktop_url"] as? String).flatMap(URL.init(string:)),
            slug: map["slug"] as? String,
            tags: map["tags"] as? [String],
            metadata: (map["metadata"] as? [String: Any]).flatMap(toLinkMetadataMap),
            iosClipboardEnabled: map["ios_clipboard_enabled"] as? Bool,
            iosFallbackUrl: (map["ios_fallback_url"] as? String).flatMap(URL.init(string:)),
            androidFallbackUrl: (map["android_fallback_url"] as? String).flatMap(URL.init(string:)),
            ogTitle: map["og_title"] as? String,
            ogDescription: map["og_description"] as? String,
            ogImageUrl: (map["og_image_url"] as? String).flatMap(URL.init(string:))
        )
    }

    private static func updateOptions(from map: [String: Any]) -> UpdateLinkOptions {
        var options = UpdateLinkOptions()
        if let name = map["name"] as? String { options.name = name }
        if map.keys.contains("desktop_url") {
            let url = (map["desktop_url"] as? String).flatMap(URL.init(string:))
            options.desktopUrl = .some(url)
        }
        if let tags = map["tags"] as? [String] { options.tags = tags }
        if map.keys.contains("metadata") {
            let metadata = (map["metadata"] as? [String: Any]).flatMap(toLinkMetadataMap)
            options.metadata = .some(metadata)
        }
        if let enabled = map["ios_clipboard_enabled"] as? Bool { options.iosClipboardEnabled = enabled }
        if map.keys.contains("ios_fallback_url") {
            options.iosFallbackUrl = .some((map["ios_fallback_url"] as? String).flatMap(URL.init(string:)))
        }
        if map.keys.contains("android_fallback_url") {
            options.androidFallbackUrl = .some((map["android_fallback_url"] as? String).flatMap(URL.init(string:)))
        }
        if map.keys.contains("og_title") { options.ogTitle = .some(map["og_title"] as? String) }
        if map.keys.contains("og_description") { options.ogDescription = .some(map["og_description"] as? String) }
        if map.keys.contains("og_image_url") {
            options.ogImageUrl = .some((map["og_image_url"] as? String).flatMap(URL.init(string:)))
        }
        return options
    }

    private static func toLinkMetadataMap(_ raw: [String: Any]) -> [String: LinkMetadataValue]? {
        var result: [String: LinkMetadataValue] = [:]
        for (key, value) in raw {
            guard let converted = toLinkMetadataValue(value) else { continue }
            result[key] = converted
        }
        return result
    }

    private static func toLinkMetadataValue(_ value: Any) -> LinkMetadataValue? {
        switch value {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let arr as [Any]: return .array(arr.compactMap(toLinkMetadataValue))
        case let map as [String: Any]:
            var nested: [String: LinkMetadataValue] = [:]
            for (k, v) in map { if let conv = toLinkMetadataValue(v) { nested[k] = conv } }
            return .object(nested)
        case is NSNull: return .null
        default: return nil
        }
    }

    private static func resolveLink(
        _ outcome: Result<Link, LinkSenseError>,
        result: @escaping FlutterResult
    ) {
        switch outcome {
        case .success(let link):
            result(encodeLink(link))
        case .failure(let error):
            result(flutterError(from: error))
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
            "created_at": iso.string(from: link.createdAt),
            "updated_at": iso.string(from: link.updatedAt),
        ]
    }

    private static func flutterError(from error: LinkSenseError) -> FlutterError {
        switch error {
        case .notConfigured:
            return FlutterError(code: "NOT_CONFIGURED", message: error.localizedDescription, details: nil)
        case .invalidSdkKey:
            return FlutterError(code: "INVALID_SDK_KEY", message: error.localizedDescription, details: nil)
        case .network:
            return FlutterError(code: "NETWORK", message: error.localizedDescription, details: nil)
        case .server(let code, _, let status):
            return FlutterError(code: code, message: error.localizedDescription, details: ["status": status])
        case .decodeFailure:
            return FlutterError(code: "DECODE_FAILURE", message: error.localizedDescription, details: nil)
        case .forbiddenCrossScope:
            return FlutterError(code: "FORBIDDEN_CROSS_SCOPE", message: error.localizedDescription, details: nil)
        case .forbiddenField:
            return FlutterError(code: "FORBIDDEN_FIELD", message: error.localizedDescription, details: nil)
        case .rateLimited(let retryAfter):
            return FlutterError(code: "RATE_LIMITED", message: error.localizedDescription, details: ["retryAfter": retryAfter as Any])
        }
    }
    #endif

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        if bufferedReady {
            events(bufferedDeepLink ?? "")
            bufferedDeepLink = nil
            bufferedReady = false
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
