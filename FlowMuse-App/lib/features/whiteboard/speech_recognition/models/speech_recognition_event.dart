enum SpeechRecognitionState { idle, starting, listening, stopping }

enum SpeechRecognitionErrorCode {
  permissionDenied,
  unavailable,
  busy,
  noSpeech,
  network,
  cancelled,
  unknown,
}

sealed class SpeechRecognitionEvent {
  const SpeechRecognitionEvent();
}

class SpeechRecognitionResult extends SpeechRecognitionEvent {
  const SpeechRecognitionResult(this.text, {required this.isFinal});

  final String text;
  final bool isFinal;
}

class SpeechRecognitionStateChanged extends SpeechRecognitionEvent {
  const SpeechRecognitionStateChanged(this.state);

  final SpeechRecognitionState state;
}

class SpeechRecognitionFailed extends SpeechRecognitionEvent {
  const SpeechRecognitionFailed(this.code, {this.message = ''});

  final SpeechRecognitionErrorCode code;
  final String message;
}
