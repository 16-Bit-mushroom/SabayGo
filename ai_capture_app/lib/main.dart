// SabayGo -- phone-as-camera test harness.
//
// Two ways to capture, both ending in the same YOLOv8 count -- this app
// has no ML runtime and makes no count of its own:
//
//  1. Direct: tap the button, photo goes straight to the AI node's
//     /api/audit/capture-upload. Proves the camera + inference pipeline
//     works; never touches the backend, so nothing lands in the audit
//     trail.
//  2. Dispatched: poll the FastAPI backend for a pending request (set by
//     POST /audits/trigger-phone, e.g. from the operator console or a
//     conductor). When one shows up, capture and upload through the
//     backend instead, so it reconciles against the manifest and writes
//     a real yolov8_audit_logs row -- mimicking how the Orange Pi will
//     be triggered later, except the Pi answers an inbound call and this
//     phone can't, so it polls. Still a manual tap to open the camera;
//     only the *decision to capture* comes from the backend.
//
// If a request fails, the UI shows an error, never a placeholder count:
// a silently faked audit would look authoritative and could wrongly flag
// a driver.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() => runApp(const AiCaptureApp());

class AiCaptureApp extends StatelessWidget {
  const AiCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SabayGo AI Capture',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const CaptureScreen(),
    );
  }
}

/// Mirrors backend/app/infrastructure/clients/ai_node_client.py's
/// CaptureResult -- same shape, same source of truth (the AI node).
class AuditResult {
  final int visualCount;
  final double? confidenceAvg;
  final String modelVersion;
  final double confThreshold;
  final int captureMs;
  final int inferenceMs;
  final int totalMs;
  final String snapshotB64;

  AuditResult({
    required this.visualCount,
    required this.confidenceAvg,
    required this.modelVersion,
    required this.confThreshold,
    required this.captureMs,
    required this.inferenceMs,
    required this.totalMs,
    required this.snapshotB64,
  });

  factory AuditResult.fromJson(Map<String, dynamic> j) => AuditResult(
        visualCount: j['visual_count'] as int,
        confidenceAvg: (j['confidence_avg'] as num?)?.toDouble(),
        modelVersion: j['model_version'] as String? ?? 'unknown',
        confThreshold: (j['conf_threshold'] as num?)?.toDouble() ?? 0,
        captureMs: j['capture_ms'] as int? ?? 0,
        inferenceMs: j['inference_ms'] as int? ?? 0,
        totalMs: j['total_ms'] as int? ?? 0,
        snapshotB64: j['snapshot_b64'] as String? ?? '',
      );
}

/// Thrown for every failure path. Carries the AI node's own error message
/// where there is one, so the UI never has to guess what went wrong.
class AiNodeException implements Exception {
  final String message;
  AiNodeException(this.message);
  @override
  String toString() => message;
}

/// Talks to the same /api/audit/... surface ai_node_client.py talks to,
/// just the upload variant instead of the server-camera one.
class AiNodeApi {
  final String baseUrl;
  final String apiKey;

  AiNodeApi({required this.baseUrl, required this.apiKey});

  Future<AuditResult> uploadCapture(File photo) async {
    final uri = Uri.parse('$baseUrl/api/audit/capture-upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers['X-API-Key'] = apiKey
      ..files.add(await http.MultipartFile.fromPath('image', photo.path));

    final http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(const Duration(seconds: 30));
    } on Exception {
      throw AiNodeException(
        'Could not reach the AI node at $baseUrl. No audit was performed.',
      );
    }

    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 401) {
      throw AiNodeException('AI node rejected the API key.');
    }
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        detail = (body['detail'] ?? body['error'] ?? res.body).toString();
      } catch (_) {
        // body wasn't JSON -- fall back to the raw text above.
      }
      throw AiNodeException('AI node error ${res.statusCode}: $detail');
    }

    return AuditResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

/// A trip/leg the backend wants captured. Set by POST /audits/trigger-phone,
/// read by polling GET /audits/phone/pending.
class PendingCapture {
  final String tripId;
  final int legSequence;
  final DateTime requestedAt;

  PendingCapture({
    required this.tripId,
    required this.legSequence,
    required this.requestedAt,
  });

  factory PendingCapture.fromJson(Map<String, dynamic> j) => PendingCapture(
        tripId: j['trip_id'] as String,
        legSequence: j['leg_sequence'] as int,
        requestedAt: DateTime.parse(j['requested_at'] as String),
      );
}

/// Mirrors backend/app/api/v1/audits.py's AuditResponse -- the real
/// reconciliation result, not just what the AI node saw. Distinct from
/// AuditResult (the direct-to-AI-node shape) because this one has been
/// checked against the manifest and written to yolov8_audit_logs.
class PhoneAuditResult {
  final String auditId;
  final String tripId;
  final int legSequence;
  final int visualCount;
  final int bookedCount;
  final int variance;
  final String resolutionStatus;
  final bool alertRaised;
  final String message;

  PhoneAuditResult({
    required this.auditId,
    required this.tripId,
    required this.legSequence,
    required this.visualCount,
    required this.bookedCount,
    required this.variance,
    required this.resolutionStatus,
    required this.alertRaised,
    required this.message,
  });

  factory PhoneAuditResult.fromJson(Map<String, dynamic> j) => PhoneAuditResult(
        auditId: j['audit_id'] as String,
        tripId: j['trip_id'] as String,
        legSequence: j['leg_sequence'] as int,
        visualCount: j['visual_count'] as int,
        bookedCount: j['booked_count'] as int,
        variance: j['variance'] as int,
        resolutionStatus: j['resolution_status'] as String,
        alertRaised: j['alert_raised'] as bool,
        message: j['message'] as String,
      );
}

/// Thrown for every backend failure path, same reasoning as AiNodeException.
class BackendException implements Exception {
  final String message;
  BackendException(this.message);
  @override
  String toString() => message;
}

/// Talks to the backend's phone-dispatch endpoints -- polling for a
/// pending request and fulfilling it -- instead of the AI node directly.
/// This is the path that lands in the real audit trail.
class BackendApi {
  final String baseUrl;
  final String deviceKey;

  BackendApi({required this.baseUrl, required this.deviceKey});

  Future<PendingCapture?> pollPending() async {
    final uri = Uri.parse('$baseUrl/audits/phone/pending');
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {'X-Device-Key': deviceKey})
          .timeout(const Duration(seconds: 10));
    } on Exception {
      throw BackendException('Could not reach the backend at $baseUrl.');
    }

    if (res.statusCode == 401) {
      throw BackendException('Backend rejected the device key.');
    }
    if (res.statusCode >= 400) {
      throw BackendException('Backend returned ${res.statusCode}.');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body.isEmpty) return null; // nothing pending
    return PendingCapture.fromJson(body);
  }

  Future<PhoneAuditResult> fulfill(File photo) async {
    final uri = Uri.parse('$baseUrl/audits/phone/fulfill');
    final request = http.MultipartRequest('POST', uri)
      ..headers['X-Device-Key'] = deviceKey
      ..files.add(await http.MultipartFile.fromPath('image', photo.path));

    final http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(const Duration(seconds: 30));
    } on Exception {
      throw BackendException(
        'Could not reach the backend at $baseUrl. No audit was performed.',
      );
    }

    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 401) {
      throw BackendException('Backend rejected the device key.');
    }
    if (res.statusCode == 409) {
      throw BackendException(
        'The pending request was already fulfilled or expired. '
        'Ask dispatch to trigger again.',
      );
    }
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        detail = (body['detail'] ?? body['error'] ?? res.body).toString();
      } catch (_) {
        // body wasn't JSON -- fall back to the raw text above.
      }
      throw BackendException('Backend error ${res.statusCode}: $detail');
    }

    return PhoneAuditResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

enum _Status { idle, uploading, done, error }

enum _DispatchStatus { idle, waiting, capturing, done, error }

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  // Runtime-configurable, not baked into the source -- same reasoning as
  // mobile/'s --dart-define=API_BASE_URL: the server PC's LAN address
  // changes machine to machine and must never be hardcoded.
  final _baseUrlController = TextEditingController(
    text: const String.fromEnvironment(
      'AI_NODE_URL',
      defaultValue: 'http://192.168.1.8:5000',
    ),
  );
  final _apiKeyController = TextEditingController(
    text: const String.fromEnvironment('AI_NODE_API_KEY', defaultValue: ''),
  );

  final _backendUrlController = TextEditingController(
    text: const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://192.168.1.8:8000/api/v1',
    ),
  );
  final _deviceKeyController = TextEditingController(
    text: const String.fromEnvironment('PHONE_DEVICE_KEY', defaultValue: ''),
  );

  final _picker = ImagePicker();

  _Status _status = _Status.idle;
  AuditResult? _result;
  String? _errorMessage;

  bool _listening = false;
  Timer? _pollTimer;
  PendingCapture? _pendingRequest;
  _DispatchStatus _dispatchStatus = _DispatchStatus.idle;
  PhoneAuditResult? _dispatchResult;
  String? _dispatchError;

  // Identifies the request the camera has already been auto-opened for,
  // so a poll tick mid-capture (or a repeat sighting of the same request
  // after a cancel) doesn't relaunch the camera on top of itself. Cleared
  // whenever a *different* request shows up.
  String? _autoOpenedFor;

  BackendApi get _backendApi => BackendApi(
        baseUrl: _backendUrlController.text.trim(),
        deviceKey: _deviceKeyController.text.trim(),
      );

  void _setListening(bool value) {
    _pollTimer?.cancel();
    setState(() {
      _listening = value;
      _pendingRequest = null;
      _dispatchStatus = _DispatchStatus.idle;
      _dispatchError = null;
      _autoOpenedFor = null;
    });
    if (!value) return;
    _pollPending(); // check immediately, then every 5s
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollPending());
  }

  Future<void> _pollPending() async {
    // A capture is already in flight -- don't let a poll tick race it.
    if (_dispatchStatus == _DispatchStatus.capturing) return;
    try {
      final pending = await _backendApi.pollPending();
      if (!mounted) return;
      setState(() {
        _pendingRequest = pending;
        _dispatchError = null;
        if (pending != null && _dispatchStatus != _DispatchStatus.done) {
          _dispatchStatus = _DispatchStatus.waiting;
        }
      });
      // Dispatch drives the camera directly -- the trigger IS the open
      // command. A human still has to press the shutter in the system
      // camera UI; that's the only tap left.
      final key = pending == null
          ? null
          : '${pending.tripId}|${pending.legSequence}|${pending.requestedAt.toIso8601String()}';
      if (key != null && key != _autoOpenedFor) {
        _autoOpenedFor = key;
        unawaited(_captureForDispatch());
      }
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _dispatchError = e.message);
    }
  }

  Future<void> _captureForDispatch() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo == null) return; // user cancelled -- not an error state

    setState(() {
      _dispatchStatus = _DispatchStatus.capturing;
      _dispatchResult = null;
      _dispatchError = null;
    });

    try {
      final result = await _backendApi.fulfill(File(photo.path));
      if (!mounted) return;
      setState(() {
        _dispatchStatus = _DispatchStatus.done;
        _dispatchResult = result;
        _pendingRequest = null; // consumed server-side
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _dispatchStatus = _DispatchStatus.error;
        _dispatchError = e.message;
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _takeAndSend() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo == null) return; // user cancelled -- not an error state

    setState(() {
      _status = _Status.uploading;
      _result = null;
      _errorMessage = null;
    });

    final api = AiNodeApi(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );

    try {
      final result = await api.uploadCapture(File(photo.path));
      setState(() {
        _status = _Status.done;
        _result = result;
      });
    } on AiNodeException catch (e) {
      setState(() {
        _status = _Status.error;
        _errorMessage = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SabayGo — AI Capture (phone camera)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'AI node URL',
                hintText: 'http://<server-pc-ip>:5000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'AI_NODE_API_KEY',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _status == _Status.uploading ? null : _takeAndSend,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take photo & send to AI node'),
            ),
            const SizedBox(height: 24),
            _buildResult(),
            const Divider(height: 48),
            Text(
              'Dispatched capture (via backend)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _backendUrlController,
              enabled: !_listening,
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                hintText: 'http://<server-pc-ip>:8000/api/v1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _deviceKeyController,
              enabled: !_listening,
              decoration: const InputDecoration(
                labelText: 'PHONE_CAPTURE_API_KEY',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Listen for a dispatch trigger'),
              subtitle: const Text('Polls every 5s. Capturing still needs a tap.'),
              value: _listening,
              onChanged: (v) => _setListening(v),
            ),
            const SizedBox(height: 8),
            _buildDispatchStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    switch (_status) {
      case _Status.idle:
        return const Text(
          'No audit yet. The phone only captures and uploads the photo; '
          'YOLOv8 runs on the server PC.',
          style: TextStyle(color: Colors.grey),
        );
      case _Status.uploading:
        return const Center(child: CircularProgressIndicator());
      case _Status.error:
        return Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _errorMessage ?? 'Unknown error.',
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        );
      case _Status.done:
        final r = _result!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visual count: ${r.visualCount}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (r.confidenceAvg != null)
                  Text('Avg confidence: ${r.confidenceAvg!.toStringAsFixed(2)}'),
                Text('Model: ${r.modelVersion} (conf ≥ ${r.confThreshold})'),
                Text(
                  'decode ${r.captureMs}ms · inference ${r.inferenceMs}ms · '
                  'total ${r.totalMs}ms',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (r.snapshotB64.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(base64Decode(r.snapshotB64)),
                  ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildDispatchStatus() {
    if (_dispatchError != null) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_dispatchError!, style: TextStyle(color: Colors.red.shade900)),
        ),
      );
    }

    switch (_dispatchStatus) {
      case _DispatchStatus.idle:
        return Text(
          _listening
              ? 'Listening -- no request from dispatch yet.'
              : 'Not listening. Dispatch trigger comes from the operator '
                  'console or a conductor calling POST /audits/trigger-phone.',
          style: const TextStyle(color: Colors.grey),
        );
      case _DispatchStatus.waiting:
        final req = _pendingRequest!;
        return Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Capture requested',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Trip ${req.tripId}, leg ${req.legSequence}'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _captureForDispatch,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Capture'),
                ),
              ],
            ),
          ),
        );
      case _DispatchStatus.capturing:
        return const Center(child: CircularProgressIndicator());
      case _DispatchStatus.done:
        final r = _dispatchResult!;
        final flagged = r.alertRaised;
        return Card(
          color: flagged ? Colors.orange.shade50 : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip ${r.tripId}, leg ${r.legSequence}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Visual ${r.visualCount} vs booked ${r.bookedCount} '
                  '(variance ${r.variance >= 0 ? '+' : ''}${r.variance})',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('Status: ${r.resolutionStatus}'),
                Text(r.message),
              ],
            ),
          ),
        );
      case _DispatchStatus.error:
        return const SizedBox.shrink(); // handled by _dispatchError above
    }
  }
}
