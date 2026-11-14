
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences.dart';
import 'youtube_account.dart';
import 'youtube_api.dart';
import 'youtube_account_factory_stub.dart' if (dart.library.io) 'youtube_account_factory_io.dart';

/// The YouTube account for the stream settings (SPEC §12.1); null where Google sign-in is not
/// set up (web and desktop builds), which leaves only the stream key.
final youtubeAccountProvider = Provider<YouTubeAccount?>((ref) {
  final account = createYouTubeAccount(ref.watch(sharedPreferencesProvider));
  if (account != null) ref.onDispose(account.dispose);
  return account;
});

/// The account when the stream goes to one of its lives (signed in: the account wins over a
/// stream key); else null. Rebuilds on sign-in, sign-out, channel and mode changes.
final youtubeActiveAccountProvider = StreamProvider<YouTubeAccount?>((ref) async* {
  final account = ref.watch(youtubeAccountProvider);
  if (account == null) {
    yield null;
    return;
  }
  YouTubeAccount? pick() => account.email != null ? account : null;
  yield pick();
  yield* account.changes.map((_) => pick());
});

/// What the screens show of the account: mode, email and channel. A record, so dependents
/// rebuild when any of them changes (the channel arrives after the sign-in); null without an
/// account (web).
final youtubeAccountViewProvider = StreamProvider<({bool active, String? email, YouTubeChannel? channel})?>((
  ref,
) async* {
  final account = ref.watch(youtubeAccountProvider);
  if (account == null) {
    yield null;
    return;
  }
  ({bool active, String? email, YouTubeChannel? channel}) view() =>
      (active: account.active, email: account.email, channel: account.channel);
  yield view();
  yield* account.changes.map((_) => view());
});
