/// Real-time quota and tier telemetry for a MediaForge developer account.
///
/// Returned by [MediaForge.getUsage] and [MediaForgeClient.getUsage].
class MediaForgeUsage {
  /// Plan name ('spark', 'forge', 'forge+').
  final String plan;

  /// API key type ('test', 'live').
  final String keyType;

  /// Monthly operations processed so far.
  final int operationsUsed;

  /// Monthly operation allowance under the current plan.
  final int operationsLimit;

  /// Total Cloudflare R2 storage consumed in bytes.
  final int storageUsedBytes;

  /// Maximum R2 storage capacity in bytes under current plan.
  final int storageLimitBytes;

  /// Monthly egress bandwidth consumed in bytes.
  final int bandwidthUsedBytes;

  /// Monthly egress bandwidth limit in bytes.
  final int bandwidthLimitBytes;

  /// Currently active API keys created by this account.
  final int activeApiKeys;

  /// Maximum API keys allowed under the current plan.
  final int maxApiKeys;

  /// Whether direct CDN edge upload is enabled for this plan.
  final bool cdnUploadAllowed;

  /// Whether MP4 and MOV video processing is enabled.
  final bool allowVideo;

  /// Creates a new [MediaForgeUsage].
  const MediaForgeUsage({
    required this.plan,
    required this.keyType,
    required this.operationsUsed,
    required this.operationsLimit,
    required this.storageUsedBytes,
    required this.storageLimitBytes,
    required this.bandwidthUsedBytes,
    required this.bandwidthLimitBytes,
    required this.activeApiKeys,
    required this.maxApiKeys,
    required this.cdnUploadAllowed,
    required this.allowVideo,
  });

  /// Deserializes [MediaForgeUsage] from backend JSON.
  factory MediaForgeUsage.fromJson(Map<String, dynamic> json) {
    final ops = (json['operations'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final storage = (json['storage'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final bandwidth = (json['bandwidth'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final rawKeys = json['apiKeys'] ?? json['api_keys'];
    final keys = (rawKeys as Map<String, dynamic>?) ?? <String, dynamic>{};
    final features = (json['features'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    final rawStorageUsed = storage['usedBytes'] ?? storage['used_bytes'];
    final rawStorageLimit = storage['limitBytes'] ?? storage['limit_bytes'];
    final rawBwUsed = bandwidth['usedBytes'] ?? bandwidth['used_bytes'];
    final rawBwLimit = bandwidth['limitBytes'] ?? bandwidth['limit_bytes'];
    final rawCdnUpload = features['cdnUpload'] ?? features['cdn_upload'];
    final rawAllowVideo = features['allowVideo'] ?? features['allow_video'];

    return MediaForgeUsage(
      plan: (json['plan'] ?? 'spark') as String,
      keyType: (json['keyType'] ?? json['key_type'] ?? 'unknown') as String,
      operationsUsed: (ops['used'] as num?)?.toInt() ?? 0,
      operationsLimit: (ops['limit'] as num?)?.toInt() ?? 0,
      storageUsedBytes: (rawStorageUsed as num?)?.toInt() ?? 0,
      storageLimitBytes: (rawStorageLimit as num?)?.toInt() ?? 0,
      bandwidthUsedBytes: (rawBwUsed as num?)?.toInt() ?? 0,
      bandwidthLimitBytes: (rawBwLimit as num?)?.toInt() ?? 0,
      activeApiKeys: (keys['active'] as num?)?.toInt() ?? 0,
      maxApiKeys: (keys['limit'] as num?)?.toInt() ?? 0,
      cdnUploadAllowed: (rawCdnUpload as bool?) ?? false,
      allowVideo: (rawAllowVideo as bool?) ?? false,
    );
  }

  /// Percentage of monthly operation quota used (0.0 to 1.0+).
  double get operationsRatio =>
      operationsLimit > 0 ? (operationsUsed / operationsLimit) : 0.0;

  /// Percentage of storage capacity used (0.0 to 1.0+).
  double get storageRatio =>
      storageLimitBytes > 0 ? (storageUsedBytes / storageLimitBytes) : 0.0;

  /// Percentage of bandwidth allowance used (0.0 to 1.0+).
  double get bandwidthRatio =>
      bandwidthLimitBytes > 0 ? (bandwidthUsedBytes / bandwidthLimitBytes) : 0.0;

  /// Whether the monthly operations limit has been reached or exceeded.
  bool get isOperationsExhausted =>
      operationsLimit > 0 && operationsUsed >= operationsLimit;

  /// Whether storage limit has been reached.
  bool get isStorageExhausted =>
      storageLimitBytes > 0 && storageUsedBytes >= storageLimitBytes;

  @override
  String toString() =>
      'MediaForgeUsage(plan: $plan, ops: $operationsUsed/$operationsLimit, storage: $storageUsedBytes/$storageLimitBytes, cdnAllowed: $cdnUploadAllowed)';
}
