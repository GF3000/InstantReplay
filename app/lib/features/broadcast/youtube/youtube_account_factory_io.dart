import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';

import 'google_youtube_account.dart';
import 'youtube_account.dart';

/// Google sign-in is set up for Android only.
YouTubeAccount? createYouTubeAccount(SharedPreferences prefs) {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  final account = GoogleYouTubeAccount(prefs: prefs);
  unawaited(account.restore());
  return account;
}
