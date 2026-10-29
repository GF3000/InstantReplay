import 'dart:convert';
import 'dart:io';

import 'package:replay_capture_android/replay_capture_android.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Phase 0 test server: trigger saves and inspect clips from a laptop browser on the same Wi-Fi.
class SpikeServer {
  SpikeServer({required this.stats, required this.save});

  final CaptureStats? Function() stats;
  final Future<ClipInfo> Function(double pre, double post) save;

  final _capture = ReplayCapture.instance;
  HttpServer? _server;

  Future<int> start({int port = 8080}) async {
    final router = Router()
      ..get('/', (Request _) => Response.ok(_page, headers: {'content-type': 'text/html; charset=utf-8'}))
      ..get('/api/stats', (Request _) => _json(_statsJson(stats())))
      ..get('/api/clips', (Request _) async => _json([for (final c in await _readyClips()) _clipJson(c)]))
      ..post('/api/save', (Request req) async {
        final pre = double.tryParse(req.url.queryParameters['pre'] ?? '') ?? 20;
        final post = double.tryParse(req.url.queryParameters['post'] ?? '') ?? 2;
        try {
          return _json(_clipJson(await save(pre, post)));
        } catch (e) {
          return Response.internalServerError(body: '$e');
        }
      })
      ..get('/live', (Request _) => Response.ok(_livePage, headers: {'content-type': 'text/html; charset=utf-8'}))
      ..get('/api/live-stats', (Request _) async => _json([
            for (final s in await _capture.liveStats())
              {
                'viewer': s.viewerId,
                'codec': s.codec,
                'encoderImplementation': s.encoderImplementation,
                'framesPerSecond': s.framesPerSecond,
                'frameWidth': s.frameWidth,
                'frameHeight': s.frameHeight,
                'qualityLimitationReason': s.qualityLimitationReason,
              },
          ]))
      ..get('/ws', webSocketHandler(_onViewer))
      ..get('/clips/<file>', (Request req, String file) async {
        final clip = await _capture.getClip(file.replaceAll('.mp4', ''));
        final path = clip?.path;
        if (path == null) return Response.notFound('No such clip');
        return createFileHandler(path, url: req.url.path, contentType: 'video/mp4')(req);
      });

    _server = await io.serve(router.call, InternetAddress.anyIPv4, port);
    return _server!.port;
  }

  Future<void> stop() async => _server?.close(force: true);

  /// Signaling, one WebSocket per viewer: `hello{codec}` → `offer{sdp}` → `answer{sdp}`.
  void _onViewer(WebSocketChannel ws, String? _) {
    final viewerId = 'v${DateTime.now().microsecondsSinceEpoch}';
    ws.stream.listen(
      (raw) async {
        final msg = jsonDecode(raw as String) as Map<String, Object?>;
        try {
          switch (msg['type']) {
            case 'hello':
              final sdp = await _capture.liveOffer(viewerId, codec: (msg['codec'] as String?) ?? 'H264');
              ws.sink.add(jsonEncode({'type': 'offer', 'sdp': sdp}));
            case 'answer':
              await _capture.liveAnswer(viewerId, msg['sdp']! as String);
          }
        } catch (e) {
          ws.sink.add(jsonEncode({'type': 'error', 'message': '$e'}));
        }
      },
      onDone: () => _capture.liveClose(viewerId),
    );
  }

  Future<List<ClipInfo>> _readyClips() async => [
        for (final c in await _capture.listClips())
          if (c.state == ClipState.ready) c,
      ]..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

  // `name` is what the page links to under /clips/.
  Map<String, Object?> _clipJson(ClipInfo c) => {
        'name': '${c.id}.mp4',
        'bytes': c.bytes,
        'durationMs': c.durationMs,
        'fragments': c.fragments,
        'assemblyMs': c.assemblyMs,
        'extraPreRollMs': c.extraPreRollMs,
        'sha256': c.sha256,
      };

  Map<String, Object?> _statsJson(CaptureStats? s) => s == null
      ? const {}
      : {
          'fps': s.fps,
          'encodedFrames': s.encodedFrames,
          'gaps': s.gaps,
          'cameraGaps': s.cameraGaps,
          'glGaps': s.glGaps,
          'bufferMs': s.bufferMs,
          'bufferBytes': s.bufferBytes,
          'outboxClips': s.outboxClips,
          'outboxBytes': s.outboxBytes,
          'thermalStatus': s.thermalStatus,
          'thermalHeadroom': s.thermalHeadroom,
          'batteryTempC': s.batteryTempC,
          'batteryPercent': s.batteryPercent,
          'plugged': s.plugged,
        };

  Response _json(Object body) =>
      Response.ok(jsonEncode(body), headers: {'content-type': 'application/json'});

  static const _page = '''
<!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
<title>InstantReplay spike</title>
<style>
body{font:15px system-ui;background:#111;color:#eee;margin:16px}
button{font-size:18px;padding:10px 16px;margin:4px;border-radius:8px;border:0;background:#ffcc00}
pre{background:#222;padding:8px;border-radius:8px} video{width:100%;max-width:960px;background:#000}
a{color:#7cf}
</style>
<h1>InstantReplay · Phase 0</h1>
<p><a href="/live">Live view (WebRTC)</a> · <a href="/live?codec=VP8">Live view (VP8)</a></p>
<div>Save last: <button onclick=save(10)>10 s</button><button onclick=save(20)>20 s</button>
<button onclick=save(30)>30 s</button><button onclick=save(60)>60 s</button> (+2 s post-roll)</div>
<p id=msg></p>
<video id=player controls loop autoplay muted></video>
<h2>Stats</h2><pre id=stats></pre>
<h2>Clips</h2><ul id=clips></ul>
<script>
async function save(pre){
  const t=performance.now(); msg.textContent='Saving '+pre+' s…';
  const r=await fetch('/api/save?pre='+pre+'&post=2',{method:'POST'});
  if(!r.ok){msg.textContent='Error: '+await r.text();return}
  const c=await r.json();
  msg.textContent=c.name+' · '+(c.bytes/1e6).toFixed(1)+' MB · '+(c.durationMs/1000).toFixed(1)+' s · assembly '+c.assemblyMs+' ms · request '+Math.round(performance.now()-t)+' ms';
  player.src='/clips/'+c.name; loadClips();
}
async function loadClips(){
  const l=await (await fetch('/api/clips')).json();
  clips.innerHTML=l.map(c=>'<li><a href="/clips/'+c.name+'" onclick="player.src=this.href;return false">'+c.name+'</a> '+(c.bytes/1e6).toFixed(1)+' MB</li>').join('');
}
setInterval(async()=>{stats.textContent=JSON.stringify(await (await fetch('/api/stats')).json(),null,1)},1000);
loadClips();
</script>
''';

  /// Live view with an on-screen millisecond clock: point the camera at this page and compare
  /// the clock with its image in the video to read glass-to-glass latency from one screenshot.
  static const _livePage = '''
<!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
<title>InstantReplay live</title>
<style>
body{font:15px system-ui;background:#111;color:#eee;margin:12px}
#row{display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap}
#clock{font:bold 64px ui-monospace,monospace;background:#fff;color:#000;padding:8px 16px;border-radius:8px;min-width:6ch}
video{width:min(100%,960px);background:#000;border-radius:8px}
pre{background:#222;padding:8px;border-radius:8px;font-size:13px}
</style>
<div id=row><div id=clock>0</div><video id=v autoplay playsinline muted></video></div>
<p id=state>connecting…</p>
<pre id=stats></pre>
<script>
const codec=new URLSearchParams(location.search).get('codec')||'H264';
const clock=document.getElementById('clock');
(function tick(){clock.textContent=String(Date.now()%100000).padStart(5,'0');requestAnimationFrame(tick)})();
const pc=new RTCPeerConnection({iceServers:[]});
pc.ontrack=e=>{v.srcObject=e.streams[0]||new MediaStream([e.track]);
  try{e.receiver.jitterBufferTarget=0}catch(_){}
  try{e.receiver.playoutDelayHint=0}catch(_){} };
pc.onconnectionstatechange=()=>state.textContent='connection: '+pc.connectionState+' · codec pref '+codec;
const ws=new WebSocket('ws://'+location.host+'/ws');
ws.onopen=()=>ws.send(JSON.stringify({type:'hello',codec}));
ws.onmessage=async m=>{
  const msg=JSON.parse(m.data);
  if(msg.type==='error'){state.textContent='error: '+msg.message;return}
  if(msg.type!=='offer')return;
  await pc.setRemoteDescription({type:'offer',sdp:msg.sdp});
  await pc.setLocalDescription(await pc.createAnswer());
  await new Promise(r=>{if(pc.iceGatheringState==='complete')return r();
    pc.onicegatheringstatechange=()=>pc.iceGatheringState==='complete'&&r(); setTimeout(r,2000)});
  ws.send(JSON.stringify({type:'answer',sdp:pc.localDescription.sdp}));
};
setInterval(async()=>{
  const r=await pc.getStats(); let s={};
  r.forEach(x=>{if(x.type==='inbound-rtp'&&x.kind==='video'){
    const codec=r.get(x.codecId);
    s={codec:codec&&codec.mimeType,decoder:x.decoderImplementation,fps:x.framesPerSecond,
       size:x.frameWidth+'x'+x.frameHeight,jitterBufferMs:x.jitterBufferEmittedCount?
       Math.round(1000*x.jitterBufferDelay/x.jitterBufferEmittedCount):null,
       framesDropped:x.framesDropped,packetsLost:x.packetsLost,bytes:x.bytesReceived}}
    if(x.type==='candidate-pair'&&x.nominated&&x.state==='succeeded')s.rttMs=Math.round(1000*(x.currentRoundTripTime||0));});
  let sender=[];try{sender=await (await fetch('/api/live-stats')).json()}catch(_){}
  stats.textContent=JSON.stringify({viewer:s,sender},null,1);
},1000);
</script>
''';
}
