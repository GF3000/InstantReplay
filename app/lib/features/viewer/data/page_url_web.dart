import 'package:replay_protocol/replay_protocol.dart';
import 'package:web/web.dart' as web;

void stripTokenFromPageUrl() {
  final current = Uri.parse(web.window.location.href);
  if (!current.queryParameters.containsKey(Api.tokenParam)) return;
  final query = Map.of(current.queryParameters)..remove(Api.tokenParam);
  final clean = Uri(
    scheme: current.scheme,
    host: current.host,
    port: current.port,
    path: current.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: current.hasFragment ? current.fragment : null,
  );
  // Keep the router's history state; only the visible URL changes.
  web.window.history.replaceState(web.window.history.state, '', clean.toString());
}
