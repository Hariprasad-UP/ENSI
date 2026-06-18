import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Derive the **Short Authentication String** shown on both devices during
/// pairing (FR-4). The code is a deterministic function of the two TLS cert
/// [fingerprints], so both peers compute the **same** 6 digits independently —
/// nothing secret is sent over the wire. The human compares the two screens and
/// approves; this is what makes pairing MITM-resistant.
///
/// Symmetric: `sasCode(a, b) == sasCode(b, a)` (fingerprints are sorted first).
String sasCode(String fingerprintA, String fingerprintB) {
  final ordered = [fingerprintA, fingerprintB]..sort();
  final digest =
      sha256.convert(utf8.encode('${ordered[0]}:${ordered[1]}')).bytes;
  // Fold the first 4 bytes into a positive 31-bit int, then take 6 digits.
  final n = ((digest[0] << 24) |
          (digest[1] << 16) |
          (digest[2] << 8) |
          digest[3]) &
      0x7fffffff;
  return (n % 1000000).toString().padLeft(6, '0');
}
