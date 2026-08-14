import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

class VoiceNoteCapture {
  const VoiceNoteCapture({
    required this.bytes,
    required this.fileName,
    required this.durationMs,
  });

  final Uint8List bytes;
  final String fileName;
  final int durationMs;
}

/// Records a voice note with the existing WebRTC stack (no extra recorder plugin).
class VoiceNoteRecorder {
  MediaRecorder? _recorder;
  MediaStream? _stream;
  String? _path;
  DateTime? _started;

  bool get isRecording => _recorder != null;

  Future<void> start() async {
    if (_recorder != null) {
      throw StateError('voice_already_recording');
    }
    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    final recorder = MediaRecorder();
    await recorder.start(_path!, audioChannel: RecorderAudioChannel.INPUT);
    _recorder = recorder;
    _started = DateTime.now();
  }

  Future<VoiceNoteCapture> stop() async {
    final recorder = _recorder;
    final path = _path;
    final started = _started;
    _recorder = null;
    _path = null;
    _started = null;
    if (recorder == null || path == null || started == null) {
      throw StateError('voice_not_recording');
    }
    await recorder.stop();
    _stream?.getTracks().forEach((track) => track.stop());
    _stream = null;
    final file = File(path);
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    return VoiceNoteCapture(
      bytes: bytes,
      fileName: 'voice.m4a',
      durationMs: DateTime.now().difference(started).inMilliseconds,
    );
  }

  Future<void> cancel() async {
    try {
      await _recorder?.stop();
    } catch (_) {}
    _recorder = null;
    _stream?.getTracks().forEach((track) => track.stop());
    _stream = null;
    final path = _path;
    _path = null;
    _started = null;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}
