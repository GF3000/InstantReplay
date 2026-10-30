import 'package:flutter/foundation.dart';
import 'package:replay_protocol/replay_protocol.dart';

/// Save button durations (D11): the big button uses [defaultSeconds]; the chips save at once with
/// their own duration. All three are set in Settings.
@immutable
class SavePresets {
  const SavePresets({this.defaultSeconds = 20, this.quickSeconds = const [10, 30, 60], this.postSeconds = 2});

  /// Durations offered in Settings. The Camera's ring buffer holds the longest one plus post-roll
  /// and a margin (SPEC §3.2), so nothing above 60 s.
  static const durationOptions = [5, 10, 15, 20, 30, 45, 60];
  static const maxQuick = 3;
  static const maxPostSeconds = 5;

  final int defaultSeconds;

  /// Ascending, 1 to [maxQuick] values from [durationOptions].
  final List<int> quickSeconds;
  final int postSeconds;

  SaveClipRequest request({required String requestId, required String viewerId, int? seconds}) => SaveClipRequest(
        requestId: requestId,
        preSeconds: (seconds ?? defaultSeconds).toDouble(),
        postSeconds: postSeconds.toDouble(),
        viewerId: viewerId,
      );

  SavePresets copyWith({int? defaultSeconds, List<int>? quickSeconds, int? postSeconds}) => SavePresets(
        defaultSeconds: defaultSeconds ?? this.defaultSeconds,
        quickSeconds: quickSeconds ?? this.quickSeconds,
        postSeconds: postSeconds ?? this.postSeconds,
      );

  @override
  bool operator ==(Object other) =>
      other is SavePresets &&
      other.defaultSeconds == defaultSeconds &&
      listEquals(other.quickSeconds, quickSeconds) &&
      other.postSeconds == postSeconds;

  @override
  int get hashCode => Object.hash(defaultSeconds, Object.hashAll(quickSeconds), postSeconds);
}
