/// Exceptions surfaced by the LinkSense Flutter plugin.
///
/// Error codes mirror the server-side `/api/sdk/v1/*` error codes plus a
/// handful of plugin-local codes for the few conditions that don't leave
/// the device (e.g. `NOT_CONFIGURED`). Each typed exception wraps a
/// common parent — integrators can catch `LinkSenseException` broadly
/// or narrow with `is LinkSenseForbiddenCrossScopeException` etc.
///
/// The 13 typed subclasses below mirror the native Android SDK's
/// `LinkSenseError` hierarchy. Backend codes not modelled here (e.g.
/// `INVALID_FORMAT`, `BUNDLE_ID_EXISTS`, `SUBDOMAIN_TAKEN`,
/// `LINKED_REFERENCES`, `CREATE_FAILED`, etc.) ride through
/// [LinkSenseServerException] — switch on `code` for narrower handling.
sealed class LinkSenseException implements Exception {
  const LinkSenseException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'LinkSenseException($code): $message';
}

/// `configure` was never called, or it threw [LinkSenseInvalidSdkKeyException].
final class LinkSenseNotConfiguredException extends LinkSenseException {
  const LinkSenseNotConfiguredException()
      : super('LinkSense.instance.configure(...) must be called first.',
            code: 'NOT_CONFIGURED');
}

/// SDK key did not match `ls_sdk_<project>_<random>`. Thrown by `configure`;
/// the native SDK stays unconfigured.
final class LinkSenseInvalidSdkKeyException extends LinkSenseException {
  const LinkSenseInvalidSdkKeyException()
      : super('SDK key format is invalid.', code: 'INVALID_SDK_KEY');
}

/// Transport-level failure (no connectivity, timeout, TLS error, etc).
final class LinkSenseNetworkException extends LinkSenseException {
  const LinkSenseNetworkException(super.message) : super(code: 'NETWORK');
}

/// Server returned a 4xx/5xx with the structured error envelope.
final class LinkSenseServerException extends LinkSenseException {
  const LinkSenseServerException(String code, super.message, this.status)
      : super(code: code);

  final int status;
}

/// SDK key is not allowed to mutate the link being targeted
/// (`FORBIDDEN_CROSS_SCOPE`).
final class LinkSenseForbiddenCrossScopeException extends LinkSenseException {
  const LinkSenseForbiddenCrossScopeException()
      : super('This SDK key cannot modify that link.',
            code: 'FORBIDDEN_CROSS_SCOPE');
}

/// Request body contained a disallowed field (`FORBIDDEN_FIELD`).
final class LinkSenseForbiddenFieldException extends LinkSenseException {
  const LinkSenseForbiddenFieldException()
      : super(
            'Request body contains a field not allowed for SDK-created links.',
            code: 'FORBIDDEN_FIELD');
}

/// Rate-limited (429). `retryAfterSeconds` is the value of the
/// `Retry-After` header when the server supplied one.
final class LinkSenseRateLimitedException extends LinkSenseException {
  const LinkSenseRateLimitedException([this.retryAfterSeconds])
      : super('Rate limit exceeded.', code: 'RATE_LIMITED');

  final int? retryAfterSeconds;
}

/// Native parsed a 2xx response but it didn't match the expected schema.
/// Usually means the backend introduced a new required field the SDK
/// hasn't been updated for — upgrade the SDK.
final class LinkSenseDecodeFailureException extends LinkSenseException {
  const LinkSenseDecodeFailureException(super.message)
      : super(code: 'DECODE_FAILURE');
}

/// 401 — SDK key missing, malformed, or unknown.
final class LinkSenseUnauthorizedException extends LinkSenseException {
  const LinkSenseUnauthorizedException()
      : super('SDK key is missing, malformed, or unknown.',
            code: 'UNAUTHORIZED');
}

/// 404 — link or install not visible to this SDK key.
final class LinkSenseNotFoundException extends LinkSenseException {
  const LinkSenseNotFoundException()
      : super('Resource not found.', code: 'NOT_FOUND');
}

/// 409 — requested `slug` is already used by another link in the project
/// (native `slugExists` / `SlugExists`, server `CUSTOM_PATH_EXISTS` or
/// `SLUG_EXISTS`).
final class LinkSenseSlugExistsException extends LinkSenseException {
  const LinkSenseSlugExistsException()
      : super('That slug is already in use for this project.',
            code: 'SLUG_EXISTS');
}

/// 403 — the project's plan or the SDK key doesn't allow this
/// (`ACCESS_DENIED`): no active plan, the link quota is reached, or the SDK
/// key isn't allowed on this platform. [message] is the server's message.
/// [plan], [currentUsage] and [limit] are only set for plan-limit denials.
final class LinkSenseAccessDeniedException extends LinkSenseException {
  const LinkSenseAccessDeniedException(
    super.message, {
    this.upgradeRequired = false,
    this.plan,
    this.currentUsage,
    this.limit,
  }) : super(code: 'ACCESS_DENIED');

  /// `true` when upgrading the plan would allow the call.
  final bool upgradeRequired;
  final String? plan;
  final int? currentUsage;
  final int? limit;
}

/// 400 — server-side Zod validation failed for one or more fields.
/// [fieldErrors] is the flattened map: dotted field path → first
/// validation message. Empty when the bridge couldn't reconstruct it.
final class LinkSenseInvalidInputException extends LinkSenseException {
  const LinkSenseInvalidInputException(this.fieldErrors)
      : super('Validation failed for one or more fields.',
            code: 'INVALID_INPUT');

  final Map<String, String> fieldErrors;
}

/// Construct the right subtype from a PlatformException / internal error
/// pair. Keeps `LinkSenseException.fromPlatform` out of the hot call
/// sites; one switch-statement, updated when the native side adds codes.
LinkSenseException linkSenseExceptionFromPlatform({
  required String code,
  required String message,
  int? status,
  int? retryAfterSeconds,
  Map<String, String>? fieldErrors,
  Map<Object?, Object?>? details,
}) {
  switch (code) {
    case 'NOT_CONFIGURED':
      return const LinkSenseNotConfiguredException();
    case 'INVALID_SDK_KEY':
      return const LinkSenseInvalidSdkKeyException();
    case 'FORBIDDEN_CROSS_SCOPE':
      return const LinkSenseForbiddenCrossScopeException();
    case 'FORBIDDEN_FIELD':
      return const LinkSenseForbiddenFieldException();
    case 'RATE_LIMITED':
      return LinkSenseRateLimitedException(retryAfterSeconds);
    case 'NETWORK':
      return LinkSenseNetworkException(message);
    case 'DECODE_FAILURE':
      return LinkSenseDecodeFailureException(message);
    case 'UNAUTHORIZED':
      return const LinkSenseUnauthorizedException();
    case 'NOT_FOUND':
      return const LinkSenseNotFoundException();
    case 'SLUG_EXISTS':
    case 'CUSTOM_PATH_EXISTS':
      return const LinkSenseSlugExistsException();
    case 'ACCESS_DENIED':
      final upgrade = details?['upgradeRequired'];
      final plan = details?['plan'];
      final usage = details?['currentUsage'];
      final limit = details?['limit'];
      return LinkSenseAccessDeniedException(
        message,
        upgradeRequired: upgrade is bool && upgrade,
        plan: plan is String ? plan : null,
        currentUsage: usage is int ? usage : null,
        limit: limit is int ? limit : null,
      );
    case 'INVALID_INPUT':
      return LinkSenseInvalidInputException(
          fieldErrors ?? const <String, String>{});
    default:
      return LinkSenseServerException(code, message, status ?? 0);
  }
}
