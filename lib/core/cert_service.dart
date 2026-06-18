import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device TLS identity: a persistent self-signed RSA certificate used for
/// the encrypted transport (FR-24, NFR-4) and as the basis for pairing trust
/// (the SHA-256 of the cert DER is the device's [fingerprint], pinned on pairing
/// — see [TrustStore] and `pairing.dart`).
///
/// The keypair is generated **once** (slow: ~1-2 s) in a background isolate, then
/// the PEMs are cached in `shared_preferences`, mirroring the persistence pattern
/// in [IdentityService].
class CertService {
  final String certPem;
  final String keyPem;

  /// Lowercase hex SHA-256 of the certificate DER. Stable across restarts and
  /// identical to what a peer computes from `X509Certificate.der` over the wire.
  final String fingerprint;

  CertService._(this.certPem, this.keyPem, this.fingerprint);

  static const _certKey = 'ensi.tls.cert';
  static const _keyKey = 'ensi.tls.key';

  /// Load the persisted cert/key, or generate + persist them on first run.
  static Future<CertService> loadOrCreate(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    var certPem = prefs.getString(_certKey);
    var keyPem = prefs.getString(_keyKey);

    if (certPem == null || keyPem == null) {
      final pems = await Isolate.run(() => _generateSelfSigned('ensi-$deviceId'));
      certPem = pems['cert']!;
      keyPem = pems['key']!;
      await prefs.setString(_certKey, certPem);
      await prefs.setString(_keyKey, keyPem);
    }

    return CertService._(certPem, keyPem, fingerprintFromPem(certPem));
  }

  /// A [SecurityContext] carrying this device's cert + key. Used for both the
  /// server (host) and client sides so each can present its identity for
  /// fingerprint pinning.
  SecurityContext buildContext() {
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(utf8.encode(certPem));
    ctx.usePrivateKeyBytes(utf8.encode(keyPem));
    return ctx;
  }

  /// SHA-256 (lowercase hex) of a certificate PEM's DER bytes.
  static String fingerprintFromPem(String certPem) =>
      sha256.convert(_derFromPem(certPem)).toString();

  /// SHA-256 (lowercase hex) of a peer certificate received over TLS.
  static String fingerprintOf(X509Certificate cert) =>
      sha256.convert(cert.der).toString();

  static Uint8List _derFromPem(String pem) {
    final body = pem
        .split(RegExp(r'\r?\n'))
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    return base64.decode(body);
  }
}

/// Top-level so it can run inside [Isolate.run]. Returns PEM strings (cheaply
/// sendable across the isolate boundary).
Map<String, String> _generateSelfSigned(String commonName) {
  final pair = CryptoUtils.generateRSAKeyPair();
  final priv = pair.privateKey as pc.RSAPrivateKey;
  final pub = pair.publicKey as pc.RSAPublicKey;

  final dn = {'CN': commonName, 'O': 'ENSI'};
  final csr = X509Utils.generateRsaCsrPem(dn, priv, pub);
  final certPem = X509Utils.generateSelfSignedCertificate(
    priv,
    csr,
    3650, // ~10 years
  );
  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
  return {'cert': certPem, 'key': keyPem};
}
