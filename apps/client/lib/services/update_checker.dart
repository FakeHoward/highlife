import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Latest client metadata published as a GitHub Release asset.
class ClientReleaseInfo {
  const ClientReleaseInfo({
    required this.version,
    required this.build,
    required this.notes,
    required this.assets,
  });

  final String version;
  final int build;
  final String notes;
  final Map<String, String> assets;

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
    return ClientReleaseInfo(
      version: json['version']?.toString() ?? '',
      build: int.tryParse(json['build']?.toString() ?? '') ?? 0,
      notes: json['notes']?.toString() ?? '',
      assets: assets,
    );
  }

  String? assetForPlatform() {
    if (kIsWeb) return assets['web'] ?? assets['android'];
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => assets['android'],
      TargetPlatform.windows => assets['windows'],
      TargetPlatform.linux => assets['linux'],
      _ => assets['android'] ??
          (assets.isEmpty ? null : assets.values.first),
    };
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

class UpdateChecker {
  UpdateChecker({
    http.Client? httpClient,
    this.latestJsonUrl =
        'https://testhighlife.strangled.net/client/latest.json',
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String latestJsonUrl;

  Future<PackageInfo> currentInfo() => PackageInfo.fromPlatform();

  Future<UpdateCheckResult> check() async {
    final info = await currentInfo();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    try {
      final response = await _http.get(Uri.parse(latestJsonUrl));
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
      final newer = isNewerRelease(
        latestVersion: latest.version,
        latestBuild: latest.build,
        currentVersion: info.version,
        currentBuild: currentBuild,
      );
      if (newer) {
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
