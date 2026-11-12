/// Pure Dart models for the LinkSense plugin. These mirror the server
/// SDK allowlist (§B.1 of the mobile-SDK plan); anything the server
/// doesn't accept will round-trip through the platform channel and
/// return a `FORBIDDEN_FIELD` exception.
class LinkSenseConfiguration {
  const LinkSenseConfiguration({
    required this.sdkKey,
    this.enableClipboard = false,
    this.enableInstallReferrer = true,
    this.enableFingerprint = true,
    this.logLevel = LinkSenseLogLevel.off,
  });

  /// Publishable SDK key in the `ls_sdk_<project>_<random>` format.
  final String sdkKey;

  /// iOS only: opt-in clipboard read on first launch for deferred deep
  /// linking. Android ignores this flag (Install Referrer is used).
  final bool enableClipboard;

  /// Android only: read Google's Play Install Referrer on first launch.
  /// Default **true** — deterministic and has no user-visible effect.
  /// iOS ignores this flag.
  final bool enableInstallReferrer;

  /// Enable probabilistic fingerprint fallback. Default **true**.
  final bool enableFingerprint;

  /// Runtime log verbosity. Keep `.off` for production ship.
  final LinkSenseLogLevel logLevel;

  Map<String, Object?> toMap() => <String, Object?>{
        'sdk_key': sdkKey,
        'enable_clipboard': enableClipboard,
        'enable_install_referrer': enableInstallReferrer,
        'enable_fingerprint': enableFingerprint,
        'log_level': logLevel.name,
      };
}

enum LinkSenseLogLevel { off, error, info, debug }

/// A resolved LinkSense dynamic link.
class LinkSenseLink {
  const LinkSenseLink({
    required this.id,
    required this.projectId,
    required this.name,
    required this.slug,
    required this.fullUrl,
    this.desktopUrl,
    this.iosFallbackUrl,
    this.androidFallbackUrl,
    this.ogTitle,
    this.ogDescription,
    this.ogImageUrl,
    this.tags = const <String>[],
    this.iosClipboardEnabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String name;
  final String slug;
  final String fullUrl;
  final String? desktopUrl;
  final String? iosFallbackUrl;
  final String? androidFallbackUrl;
  final String? ogTitle;
  final String? ogDescription;
  final String? ogImageUrl;
  final List<String> tags;
  final bool iosClipboardEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory LinkSenseLink.fromMap(Map<dynamic, dynamic> raw) {
    final tagsRaw = raw['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((e) => e.toString()).toList()
        : const <String>[];
    return LinkSenseLink(
      id: raw['id'] as String,
      projectId: raw['project_id'] as String,
      name: raw['name'] as String,
      slug: (raw['custom_path'] ?? raw['slug']) as String,
      fullUrl: raw['full_url'] as String,
      desktopUrl: raw['desktop_url'] as String?,
      iosFallbackUrl: raw['ios_fallback_url'] as String?,
      androidFallbackUrl: raw['android_fallback_url'] as String?,
      ogTitle: (raw['og_title'] ?? raw['social_title']) as String?,
      ogDescription:
          (raw['og_description'] ?? raw['social_description']) as String?,
      ogImageUrl: (raw['og_image_url'] ?? raw['social_image_url']) as String?,
      tags: tags,
      iosClipboardEnabled: raw['ios_clipboard_enabled'] as bool? ?? false,
      createdAt: DateTime.parse(raw['created_at'] as String),
      updatedAt: DateTime.parse(raw['updated_at'] as String),
    );
  }
}

/// Fields accepted by `createLink`. Mirrors the server's SDK allowlist.
class CreateLinkOptions {
  const CreateLinkOptions({
    required this.name,
    this.desktopUrl,
    this.slug,
    this.tags,
    this.metadata,
    this.iosClipboardEnabled,
    this.iosFallbackUrl,
    this.androidFallbackUrl,
    this.ogTitle,
    this.ogDescription,
    this.ogImageUrl,
  });

  final String name;
  final String? desktopUrl;
  final String? slug;
  final List<String>? tags;
  final Map<String, Object?>? metadata;
  final bool? iosClipboardEnabled;
  final String? iosFallbackUrl;
  final String? androidFallbackUrl;
  final String? ogTitle;
  final String? ogDescription;
  final String? ogImageUrl;

  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        if (desktopUrl != null) 'desktop_url': desktopUrl,
        if (slug != null) 'slug': slug,
        if (tags != null) 'tags': tags,
        if (metadata != null) 'metadata': metadata,
        if (iosClipboardEnabled != null)
          'ios_clipboard_enabled': iosClipboardEnabled,
        if (iosFallbackUrl != null) 'ios_fallback_url': iosFallbackUrl,
        if (androidFallbackUrl != null)
          'android_fallback_url': androidFallbackUrl,
        if (ogTitle != null) 'og_title': ogTitle,
        if (ogDescription != null) 'og_description': ogDescription,
        if (ogImageUrl != null) 'og_image_url': ogImageUrl,
      };
}

/// PATCH fields. A `null` in the Dart map means "don't send"; pass a
/// [LinkSenseFieldClear] sentinel to send `null` explicitly (which
/// clears the field server-side).
class UpdateLinkOptions {
  const UpdateLinkOptions({
    this.name,
    this.desktopUrl,
    this.tags,
    this.metadata,
    this.iosClipboardEnabled,
    this.iosFallbackUrl,
    this.androidFallbackUrl,
    this.ogTitle,
    this.ogDescription,
    this.ogImageUrl,
  });

  final String? name;
  final Object? desktopUrl;
  final List<String>? tags;
  final Object? metadata;
  final bool? iosClipboardEnabled;
  final Object? iosFallbackUrl;
  final Object? androidFallbackUrl;
  final Object? ogTitle;
  final Object? ogDescription;
  final Object? ogImageUrl;

  Map<String, Object?> toMap() {
    final map = <String, Object?>{};
    void put(String key, Object? value) {
      if (value == null) return;
      map[key] = value is LinkSenseFieldClear ? null : value;
    }

    if (name != null) map['name'] = name;
    put('desktop_url', desktopUrl);
    if (tags != null) map['tags'] = tags;
    put('metadata', metadata);
    if (iosClipboardEnabled != null) {
      map['ios_clipboard_enabled'] = iosClipboardEnabled;
    }
    put('ios_fallback_url', iosFallbackUrl);
    put('android_fallback_url', androidFallbackUrl);
    put('og_title', ogTitle);
    put('og_description', ogDescription);
    put('og_image_url', ogImageUrl);
    return map;
  }
}

/// Marker that tells `UpdateLinkOptions.toMap` to emit JSON `null`
/// (clearing the field server-side) rather than omitting the key.
class LinkSenseFieldClear {
  const LinkSenseFieldClear();
}

const LinkSenseFieldClear linkSenseClear = LinkSenseFieldClear();
