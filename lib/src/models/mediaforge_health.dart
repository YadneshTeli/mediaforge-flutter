/// Details of an authenticated API key returned by health check.
class ApiKeyDetails {
  /// Unique key ID.
  final String id;

  /// Human-readable name/label for the key.
  final String name;

  /// Redacted key prefix (e.g. 'mf_live_9a8b...').
  final String prefix;

  /// Key type ('test' or 'live').
  final String type;

  /// Account plan associated with this key ('spark', 'forge', 'forge+').
  final String plan;

  /// Creates a new [ApiKeyDetails].
  const ApiKeyDetails({
    required this.id,
    required this.name,
    required this.prefix,
    required this.type,
    required this.plan,
  });

  /// Deserializes [ApiKeyDetails] from JSON.
  factory ApiKeyDetails.fromJson(Map<String, dynamic> json) {
    return ApiKeyDetails(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      prefix: (json['prefix'] ?? '') as String,
      type: (json['type'] ?? '') as String,
      plan: (json['plan'] ?? 'spark') as String,
    );
  }

  /// Whether this is a production live key.
  bool get isLive => type == 'live';

  /// Whether this is a test/sandbox key.
  bool get isTest => type == 'test';

  @override
  String toString() => 'ApiKeyDetails(id: $id, type: $type, plan: $plan, prefix: $prefix)';
}

/// Health and connectivity status of the MediaForge Developer API.
///
/// Returned by [MediaForge.checkHealth] and [MediaForgeClient.checkHealth].
class MediaForgeHealth {
  /// Health status ('ok', 'unhealthy').
  final String status;

  /// Service name string ('MediaForge Developer API').
  final String service;

  /// API version string (e.g. '1.0.0').
  final String version;

  /// Server timestamp in UTC.
  final DateTime timestamp;

  /// Whether the request included a valid, recognized API key.
  final bool authenticated;

  /// Associated API key and plan details if authenticated.
  final ApiKeyDetails? apiKey;

  /// Error message if status is unhealthy.
  final String? error;

  /// Creates a new [MediaForgeHealth].
  const MediaForgeHealth({
    required this.status,
    required this.service,
    required this.version,
    required this.timestamp,
    required this.authenticated,
    this.apiKey,
    this.error,
  });

  /// Deserializes [MediaForgeHealth] from JSON.
  factory MediaForgeHealth.fromJson(Map<String, dynamic> json) {
    final rawKey = json['apiKey'] ?? json['api_key'];
    final keyDetails = rawKey is Map<String, dynamic>
        ? ApiKeyDetails.fromJson(rawKey)
        : null;

    final rawTs = json['timestamp'];
    final parsedTs = rawTs != null
        ? DateTime.parse(rawTs as String)
        : DateTime.now().toUtc();

    return MediaForgeHealth(
      status: (json['status'] ?? 'ok') as String,
      service: (json['service'] ?? 'MediaForge Developer API') as String,
      version: (json['version'] ?? '1.0.0') as String,
      timestamp: parsedTs,
      authenticated: (json['authenticated'] as bool?) ?? false,
      apiKey: keyDetails,
      error: json['error'] as String?,
    );
  }

  /// Whether the server is healthy.
  bool get isHealthy => status.toLowerCase() == 'ok';

  @override
  String toString() =>
      'MediaForgeHealth(status: $status, authenticated: $authenticated, plan: ${apiKey?.plan})';
}
