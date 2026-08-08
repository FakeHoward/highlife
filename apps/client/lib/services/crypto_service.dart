import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Thin wrapper around famedly `Client.encryption` and crypto-setup helpers.
///
/// On Flutter web, [available] is false when the dummy native implementation
/// is used — callers must not pretend key backup is enabled.
class CryptoService {
  CryptoService(this.client, {required this.platformCryptoReady});

  final Client client;

  /// False on web (dummy vodozemac) or when the SDK reports encryption off.
  final bool platformCryptoReady;

  Encryption? get encryption => client.encryption;

  bool get available =>
      platformCryptoReady &&
      client.encryptionEnabled &&
      client.encryption != null;

  Stream<KeyVerification> get onIncomingVerification =>
      client.onKeyVerificationRequest.stream;

  List<DeviceKeys> ownDevices({bool excludeSelf = true}) {
    final userId = client.userID;
    if (userId == null) return const [];
    final list = client.userDeviceKeys[userId];
    if (list == null) return const [];
    return list.deviceKeys.values.where((device) {
      if (!excludeSelf) return true;
      return device.deviceId != client.deviceID;
    }).toList(growable: false);
  }

  Future<KeyVerification> startDeviceVerification(DeviceKeys device) {
    if (!available) {
      throw StateError('Encryption is not available on this platform');
    }
    return device.startVerification();
  }

  Future<({bool connected, bool initialized})> identityState() async {
    if (!available) {
      return (connected: false, initialized: false);
    }
    return client.getCryptoIdentityState();
  }

  /// Creates secret storage + cross-signing + optional online key backup.
  /// Returns the recovery key when secret storage is newly created.
  Future<String> initIdentity({String? passphrase}) {
    if (!available) {
      throw StateError(
        'Key backup setup requires a native crypto backend (not available on web)',
      );
    }
    return client.initCryptoIdentity(passphrase: passphrase);
  }

  Future<void> restoreIdentity(String keyOrPassphrase) {
    if (!available) {
      throw StateError(
        'Key backup restore requires a native crypto backend (not available on web)',
      );
    }
    return client.restoreCryptoIdentity(keyOrPassphrase);
  }

  static String unavailableReason({required bool isWeb}) {
    if (isWeb || kIsWeb) {
      return 'E2EE unavailable: vodozemac WASM failed or is not deployed (dummy crypto backend).';
    }
    return 'E2EE unavailable: native vodozemac init failed or encryption is disabled.';
  }
}
