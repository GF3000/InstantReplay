import 'package:replay_protocol/replay_protocol.dart';

/// Save button durations (D11): the big button uses [defaultSeconds]; the chips save at once with
/// their own duration. Post-roll is fixed at 2 s until the settings screen exists.
class SavePresets {
  const SavePresets({this.defaultSeconds = 20, this.quickSeconds = const [10, 30, 60], this.postSeconds = 2});

  final int defaultSeconds;
  final List<int> quickSeconds;
  final int postSeconds;

  SaveClipRequest request({required String requestId, required String viewerId, int? seconds}) => SaveClipRequest(
        requestId: requestId,
        preSeconds: (seconds ?? defaultSeconds).toDouble(),
        postSeconds: postSeconds.toDouble(),
        viewerId: viewerId,
      );
}
