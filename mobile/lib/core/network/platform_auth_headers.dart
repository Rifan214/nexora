import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/instagram_auth_provider.dart';
import '../../providers/tiktok_auth_provider.dart';
import '../../providers/x_auth_provider.dart';

bool isXUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final host = uri?.host.toLowerCase() ?? '';
  return host == 'twitter.com' ||
      host.endsWith('.twitter.com') ||
      host == 'x.com' ||
      host.endsWith('.x.com');
}

bool isTikTokUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final host = uri?.host.toLowerCase() ?? '';
  return host == 'tiktok.com' ||
      host.endsWith('.tiktok.com') ||
      host == 'vxtiktok.com' ||
      host.endsWith('.vxtiktok.com');
}

bool isInstagramUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final host = uri?.host.toLowerCase() ?? '';
  return host == 'instagram.com' || host.endsWith('.instagram.com');
}

bool isSessionInvalidationMessage(String message) {
  final msg = message.toLowerCase();
  return msg.contains('session not found') ||
      msg.contains('session has expired') ||
      msg.contains('session is invalid') ||
      msg.contains('x authentication session') ||
      msg.contains('tiktok authentication session') ||
      msg.contains('instagram authentication session');
}

Map<String, dynamic>? buildAuthHeadersForUrl(Ref ref, String url) {
  if (isXUrl(url)) {
    final xSessionId = ref.read(activeXSessionIdProvider);
    if (xSessionId != null && xSessionId.isNotEmpty) {
      return {'X-Session-ID': xSessionId};
    }
  } else if (isTikTokUrl(url)) {
    final tikTokSessionId = ref.read(activeTikTokSessionIdProvider);
    if (tikTokSessionId != null && tikTokSessionId.isNotEmpty) {
      return {'TikTok-Session-ID': tikTokSessionId};
    }
  } else if (isInstagramUrl(url)) {
    final instagramSessionId = ref.read(activeInstagramSessionIdProvider);
    if (instagramSessionId != null && instagramSessionId.isNotEmpty) {
      return {'Instagram-Session-ID': instagramSessionId};
    }
  }
  return null;
}

Future<void> handleSessionInvalidationForUrl(
  Ref ref,
  String url, {
  required String message,
}) async {
  if (!isSessionInvalidationMessage(message)) {
    return;
  }
  final isExpired = message.toLowerCase().contains('expired');
  if (isXUrl(url)) {
    await ref
        .read(xAuthProvider.notifier)
        .handleSessionInvalidated(isExpired: isExpired, reason: message);
  } else if (isTikTokUrl(url)) {
    await ref
        .read(tikTokAuthProvider.notifier)
        .handleSessionInvalidated(isExpired: isExpired, reason: message);
  } else if (isInstagramUrl(url)) {
    await ref
        .read(instagramAuthProvider.notifier)
        .handleSessionInvalidated(isExpired: isExpired, reason: message);
  }
}
