import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Hosts allowed for release assets when they differ from the latest.json host
/// (GitHub Releases + CDN redirects).
const Set<String> kDefaultReleaseAssetHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// Latest client metadata published as a GitHub Release asset.
class ClientReleaseInfo {
  const ClientReleaseInfo({
    required this.version,
    required this.build,
    required this.notes,
    required this.assets,
    this.sha256 = const {},
  });

  final String version;
  final int build;
  final String notes;
  final Map<String, String> assets;

  /// Optional per-platform hex digests (key matches [assets]).
  final Map<String, String> sha256;

  factory ClientReleaseInfo.fromJson(Map<String, dynamic> json) {
    final assetsRaw = json['assets'];
    final assets = <String, String>{};
    if (assetsRaw is Map) {
      for (final entry in assetsRaw.entries) {
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          assets[entry.key.toString()] = value;
        }
      }
    }
    final hashesRaw = json['sha256'];
    final hashes = <String, String>{};
    if (hashesRaw is Map) {
      for (final entry in hashesRaw.entries) {
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          hashes[entry.key.toString()] = value.toLowerCase();
        }
      }
    }
    return ClientReleaseInfo(
      version: json['version']?.toString() ?? '',
      build: int.tryParse(json['build']?.toString() ?? '') ?? 0,
      notes: json['notes']?.toString() ?? '',
      assets: assets,
      sha256: hashes,
    );
  }

  String? assetKeyForPlatform() {
    if (kIsWeb) {
      if (assets.containsKey('web')) return 'web';
      if (assets.containsKey('android')) return 'android';
      return null;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        assets.containsKey('android') ? 'android' : null,
      TargetPlatform.windows =>
        assets.containsKey('windows') ? 'windows' : null,
      TargetPlatform.linux => assets.containsKey('linux') ? 'linux' : null,
      _ => assets.containsKey('android')
          ? 'android'
          : (assets.isEmpty ? null : assets.keys.first),
    };
  }

  String? assetForPlatform() {
    final key = assetKeyForPlatform();
    return key == null ? null : assets[key];
  }

  String? sha256ForPlatform() {
    final key = assetKeyForPlatform();
    return key == null ? null : sha256[key];
  }
}

class UpdateCheckResult {
  const UpdateCheckResult.upToDate({
    required this.currentVersion,
    required this.currentBuild,
    required this.latest,
  })  : updateAvailable = false,
        error = null;

  const UpdateCheckResult.available({
    required this.currentVersion,
    required this.currentBuild,
    required this.latest,
  })  : updateAvailable = true,
        error = null;

  const UpdateCheckResult.failed({
    required this.currentVersion,
    required this.currentBuild,
    required this.error,
  })  : updateAvailable = false,
        latest = null;

  final String currentVersion;
  final int currentBuild;
  final ClientReleaseInfo? latest;
  final bool updateAvailable;
  final String? error;
}

/// Default updater metadata URL (mirrored on the homeserver from GitHub Releases).
const String kDefaultLatestJsonUrl = String.fromEnvironment(
  'HIGHLIFE_LATEST_JSON_URL',
  defaultValue: '',
);

class UpdateChecker {
  UpdateChecker({
    http.Client? httpClient,
    this.latestJsonUrl = kDefaultLatestJsonUrl,
    this.extraAssetHosts = const {},
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String latestJsonUrl;
  final Set<String> extraAssetHosts;

  Future<PackageInfo> currentInfo() => PackageInfo.fromPlatform();

  Future<UpdateCheckResult> check() async {
    final info = await currentInfo();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    try {
      final metaUri = Uri.parse(latestJsonUrl);
      if (!isHttpsUri(metaUri)) {
        return UpdateCheckResult.failed(
          currentVersion: info.version,
          currentBuild: currentBuild,
          error: 'latest.json must use HTTPS',
        );
      }
      final response = await _http.get(metaUri);
      if (response.statusCode != 200) {
        return UpdateCheckResult.failed(
          currentVersion: info.version,
          currentBuild: currentBuild,
          error: 'HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return UpdateCheckResult.failed(
          currentVersion: info.version,
          currentBuild: currentBuild,
          error: 'Invalid latest.json',
        );
      }
      final latest = ClientReleaseInfo.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      for (final entry in latest.assets.entries) {
        if (!isTrustedReleaseAssetUrl(
          entry.value,
          latestJsonUrl: latestJsonUrl,
          extraHosts: extraAssetHosts,
        )) {
          return UpdateCheckResult.failed(
            currentVersion: info.version,
            currentBuild: currentBuild,
            error: 'Untrusted asset URL for ${entry.key}',
          );
        }
      }
      final newer = isNewerRelease(
        latestVersion: latest.version,
        latestBuild: latest.build,
        currentVersion: info.version,
        currentBuild: currentBuild,
      );
      if (newer) {
        final integrityError = integrityGateError(latest);
        if (integrityError != null) {
          return UpdateCheckResult.failed(
            currentVersion: info.version,
            currentBuild: currentBuild,
            error: integrityError,
          );
        }
        return UpdateCheckResult.available(
          currentVersion: info.version,
          currentBuild: currentBuild,
          latest: latest,
        );
      }
      return UpdateCheckResult.upToDate(
        currentVersion: info.version,
        currentBuild: currentBuild,
        latest: latest,
      );
    } catch (e) {
      return UpdateCheckResult.failed(
        currentVersion: info.version,
        currentBuild: currentBuild,
        error: e.toString(),
      );
    }
  }
}

bool isHttpsUri(Uri uri) => uri.isScheme('https') && uri.host.isNotEmpty;

/// Asset URL must be HTTPS and either share the latest.json host or sit on a
/// small release-host allowlist.
bool isTrustedReleaseAssetUrl(
  String assetUrl, {
  required String latestJsonUrl,
  Set<String> extraHosts = const {},
}) {
  final asset = Uri.tryParse(assetUrl);
  final meta = Uri.tryParse(latestJsonUrl);
  if (asset == null || meta == null) return false;
  if (!isHttpsUri(asset) || !isHttpsUri(meta)) return false;
  if (asset.host == meta.host) return true;
  final allowed = {...kDefaultReleaseAssetHosts, ...extraHosts};
  return allowed.contains(asset.host);
}

bool isSha256Hex(String value) =>
    RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

/// Native desktop/mobile installs require a matching sha256 in latest.json.
/// Web stays optional for backward compatibility with static hosting.
bool platformRequiresIntegrityHash() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.windows ||
    TargetPlatform.linux =>
      true,
    _ => false,
  };
}

/// Returns an error message when integrity metadata is unacceptable, else null.
String? integrityGateError(ClientReleaseInfo latest) {
  final key = latest.assetKeyForPlatform();
  if (key == null) return null;
  final hash = latest.sha256[key];
  if (hash != null && hash.isNotEmpty) {
    if (!isSha256Hex(hash)) return 'Invalid sha256 for $key';
    return null;
  }
  if (platformRequiresIntegrityHash()) {
    return 'Missing sha256 for $key update asset';
  }
  assert(() {
    debugPrint('UpdateChecker: no sha256 for $key; allowing (web/compat)');
    return true;
  }());
  return null;
}

/// Fail closed when [expectedHex] is present but does not match [bytes].
bool verifyAssetSha256(List<int> bytes, String expectedHex) {
  if (!isSha256Hex(expectedHex)) return false;
  final actual = sha256.convert(bytes).toString();
  return actual == expectedHex.toLowerCase();
}

bool isNewerRelease({
  required String latestVersion,
  required int latestBuild,
  required String currentVersion,
  required int currentBuild,
}) {
  final cmp = compareSemver(latestVersion, currentVersion);
  if (cmp != 0) return cmp > 0;
  return latestBuild > currentBuild;
}

/// Returns negative if a < b, zero if equal, positive if a > b.
int compareSemver(String a, String b) {
  List<int> parts(String value) {
    return value
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9].*'), '')) ?? 0)
        .toList();
  }

  final left = parts(a);
  final right = parts(b);
  final len = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < len; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}
