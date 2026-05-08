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
  final List<String> _urls = [];

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_capturing) {
        await rust_capture.stopCapture();
        setState(() => _capturing = false);
      } else {
        await rust_capture.startCapture();
        setState(() => _capturing = true);
      }
    } catch (e) {
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
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(_urls[i], maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
