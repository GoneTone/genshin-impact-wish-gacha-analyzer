import 'dart:async';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart' as rust_capture;

class PocCapturePage extends StatefulWidget {
  const PocCapturePage({super.key});

  @override
  State<PocCapturePage> createState() => _PocCapturePageState();
}

class _PocCapturePageState extends State<PocCapturePage> {
  bool _capturing = false;
  String? _error;
  final List<rust_capture.CapturedRequest> _urls = [];
  StreamSubscription<rust_capture.CapturedRequest>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_capturing) {
        await _sub?.cancel();
        _sub = null;
        await rust_capture.stopCapture();
        if (!mounted) return;
        setState(() => _capturing = false);
      } else {
        final stream = rust_capture.startCapture();
        _sub = stream.listen(
          (event) {
            if (!mounted) return;
            setState(() => _urls.insert(0, event));
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _error = '$e');
          },
        );
        if (!mounted) return;
        setState(() => _capturing = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HTTPS 攔截 PoC')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _toggle,
                  child: Text(_capturing ? '停止攔截' : '開始攔截'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 8),
                Text('共 ${_urls.length} 筆'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _urls.isEmpty
                ? const Center(child: Text('尚無攔截紀錄'))
                : ListView.separated(
                    itemCount: _urls.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _urls[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${r.method}  ${r.url}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: Text(r.host),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
