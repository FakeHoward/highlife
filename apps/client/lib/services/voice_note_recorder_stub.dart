import 'dart:typed_data';

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

class VoiceNoteRecorder {
  bool get isRecording => false;

  Future<void> start() async {
    throw UnsupportedError('voice_web_unsupported');
  }

  Future<VoiceNoteCapture> stop() async {
    throw UnsupportedError('voice_web_unsupported');
  }

  Future<void> cancel() async {}
}
