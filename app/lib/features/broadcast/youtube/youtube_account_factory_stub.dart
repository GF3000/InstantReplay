import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_account.dart';

/// The web Viewer has no YouTube account: only the stream key.
YouTubeAccount? createYouTubeAccount(SharedPreferences prefs) => null;
