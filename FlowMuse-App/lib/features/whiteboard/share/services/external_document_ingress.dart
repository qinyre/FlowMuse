import '../models/external_document_request.dart';

class ExternalDocumentIngress {
  static const _maxItems = 3;
  static const _maxBytes = 20 * 1024 * 1024;
  final List<ExternalDocumentRequest> _pending = [];

  bool enqueue(ExternalDocumentRequest request) {
    if (_pending.length >= _maxItems ||
        request.bytes.lengthInBytes > _maxBytes) {
      return false;
    }
    _pending.add(request);
    return true;
  }

  Future<ExternalDocumentRequest?> takeNext() async {
    return _pending.isEmpty ? null : _pending.removeAt(0);
  }
}
