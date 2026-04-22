/// Exceptions surfaced by the LinkSense Flutter plugin.
///
/// Error codes mirror the server-side `/api/sdk/v1/*` error codes plus a
/// handful of plugin-local codes for the few conditions that don't leave
/// the device (e.g. `NOT_CONFIGURED`). Each typed exception wraps a
/// common parent — integrators can catch `LinkSenseException` broadly
/// or narrow with `is LinkSenseForbiddenCrossScope` etc.
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
      : super('LinkSense.instance.configure(...) must be called first.', code: 'NOT_CONFIGURED');
}

/// SDK key did not match `ls_sdk_<project>_<random>`.
final class LinkSenseInvalidSdkKey extends LinkSenseException {
  const LinkSenseInvalidSdkKey()
      : super('SDK key format is invalid.', code: 'INVALID_SDK_KEY');
}

/// Transport-level failure (no connectivity, timeout, TLS error, etc).
final class LinkSenseNetworkException extends LinkSenseException {
  const LinkSenseNetworkException(String message) : super(message, code: 'NETWORK');
}

/// Server returned a 4xx/5xx with the structured error envelope.
final class LinkSenseServerException extends LinkSenseException {
  const LinkSenseServerException(String code, super.message, this.status) : super(code: code);

  final int status;
}

/// SDK key is not allowed to mutate the link being targeted
/// (`FORBIDDEN_CROSS_SCOPE`).
final class LinkSenseForbiddenCrossScope extends LinkSenseException {
  const LinkSenseForbiddenCrossScope()
      : super('This SDK key cannot modify that link.', code: 'FORBIDDEN_CROSS_SCOPE');
}

/// Request body contained a disallowed field (`FORBIDDEN_FIELD`).
final class LinkSenseForbiddenField extends LinkSenseException {
  const LinkSenseForbiddenField()
      : super('Request body contains a field not allowed for SDK-created links.', code: 'FORBIDDEN_FIELD');
}

/// Rate-limited (429). `retryAfterSeconds` is the value of the
/// `Retry-After` header when the server supplied one.
final class LinkSenseRateLimited extends LinkSenseException {
  const LinkSenseRateLimited([this.retryAfterSeconds])
      : super('Rate limit exceeded.', code: 'RATE_LIMITED');

  final int? retryAfterSeconds;
}

/// Construct the right subtype from a PlatformException / internal error
/// pair. Keeps `LinkSenseException.fromPlatform` out of the hot call
/// sites; one switch-statement, updated when the native side adds codes.
LinkSenseException linkSenseExceptionFromPlatform({
  required String code,
  required String message,
  int? status,
  int? retryAfter,
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
    default:
      return LinkSenseServerException(code, message, status ?? 0);
  }
}
