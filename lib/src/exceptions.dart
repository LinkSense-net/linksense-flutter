/// Exceptions surfaced by the LinkSense Flutter plugin.
///
/// Error codes mirror the server-side `/api/sdk/v1/*` error codes plus a
/// handful of plugin-local codes for the few conditions that don't leave
/// the device (e.g. `NOT_CONFIGURED`). Each typed exception wraps a
/// common parent — integrators can catch `LinkSenseException` broadly
/// or narrow with `is LinkSenseForbiddenCrossScope` etc.
///
/// The 12 typed subclasses below mirror the native Android SDK's
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

/// `configure` was never called, or was called with an invalid SDK key.
final class LinkSenseNotConfigured extends LinkSenseException {
  const LinkSenseNotConfigured()
      : super('LinkSense.instance.configure(...) must be called first.',
            code: 'NOT_CONFIGURED');
}

/// SDK key did not match `ls_sdk_<project>_<random>`.
final class LinkSenseInvalidSdkKey extends LinkSenseException {
  const LinkSenseInvalidSdkKey()
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
final class LinkSenseForbiddenCrossScope extends LinkSenseException {
  const LinkSenseForbiddenCrossScope()
      : super('This SDK key cannot modify that link.',
            code: 'FORBIDDEN_CROSS_SCOPE');
}

/// Request body contained a disallowed field (`FORBIDDEN_FIELD`).
final class LinkSenseForbiddenField extends LinkSenseException {
  const LinkSenseForbiddenField()
      : super(
            'Request body contains a field not allowed for SDK-created links.',
            code: 'FORBIDDEN_FIELD');
}

/// Rate-limited (429). `retryAfterSeconds` is the value of the
/// `Retry-After` header when the server supplied one.
final class LinkSenseRateLimited extends LinkSenseException {
  const LinkSenseRateLimited([this.retryAfterSeconds])
      : super('Rate limit exceeded.', code: 'RATE_LIMITED');

  final int? retryAfterSeconds;
}

/// Native parsed a 2xx response but it didn't match the expected schema.
/// Usually means the backend introduced a new required field the SDK
/// hasn't been updated for — upgrade the SDK.
final class LinkSenseDecodeFailure extends LinkSenseException {
  const LinkSenseDecodeFailure(super.message) : super(code: 'DECODE_FAILURE');
}

/// 401 — SDK key missing, malformed, or unknown.
final class LinkSenseUnauthorized extends LinkSenseException {
  const LinkSenseUnauthorized()
      : super('SDK key is missing, malformed, or unknown.',
            code: 'UNAUTHORIZED');
}

/// 404 — link or install not visible to this SDK key.
final class LinkSenseNotFound extends LinkSenseException {
  const LinkSenseNotFound() : super('Resource not found.', code: 'NOT_FOUND');
}

/// 409 — requested `slug` is already used by another link in the project.
final class LinkSenseCustomPathExists extends LinkSenseException {
  const LinkSenseCustomPathExists()
      : super('Custom path is already taken in this project.',
            code: 'CUSTOM_PATH_EXISTS');
}

/// 400 — server-side Zod validation failed for one or more fields.
/// [fieldErrors] is the flattened map: dotted field path → first
/// validation message. Empty when the bridge couldn't reconstruct it.
final class LinkSenseInvalidInput extends LinkSenseException {
  const LinkSenseInvalidInput(this.fieldErrors)
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
  int? retryAfter,
  Map<String, String>? fieldErrors,
}) {
  switch (code) {
    case 'NOT_CONFIGURED':
      return const LinkSenseNotConfigured();
    case 'INVALID_SDK_KEY':
      return const LinkSenseInvalidSdkKey();
    case 'FORBIDDEN_CROSS_SCOPE':
      return const LinkSenseForbiddenCrossScope();
    case 'FORBIDDEN_FIELD':
      return const LinkSenseForbiddenField();
    case 'RATE_LIMITED':
      return LinkSenseRateLimited(retryAfter);
    case 'NETWORK':
      return LinkSenseNetworkException(message);
    case 'DECODE_FAILURE':
      return LinkSenseDecodeFailure(message);
    case 'UNAUTHORIZED':
      return const LinkSenseUnauthorized();
    case 'NOT_FOUND':
      return const LinkSenseNotFound();
    case 'CUSTOM_PATH_EXISTS':
      return const LinkSenseCustomPathExists();
    case 'INVALID_INPUT':
      return LinkSenseInvalidInput(fieldErrors ?? const <String, String>{});
    default:
      return LinkSenseServerException(code, message, status ?? 0);
  }
}
