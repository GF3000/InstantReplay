
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences.dart';
import 'youtube_account.dart';
import 'youtube_account_factory_stub.dart' if (dart.library.io) 'youtube_account_factory_io.dart';

/// The YouTube account for the stream settings (SPEC §12.1); null where Google sign-in is not
/// set up (web and desktop builds), which leaves only the stream key.
final youtubeAccountProvider = Provider<YouTubeAccount?>((ref) {
  final account = createYouTubeAccount(ref.watch(sharedPreferencesProvider));
  if (account != null) ref.onDispose(account.dispose);
  return account;
});

/// The account when the stream goes to one of its lives (account mode, signed in); else null.
/// Rebuilds on sign-in, sign-out and mode changes.
final youtubeActiveAccountProvider = StreamProvider<YouTubeAccount?>((ref) async* {
  final account = ref.watch(youtubeAccountProvider);
  if (account == null) {
    yield null;
    return;
  }
  YouTubeAccount? pick() => account.active && account.email != null ? account : null;
  yield pick();
  yield* account.changes.map((_) => pick());
});
