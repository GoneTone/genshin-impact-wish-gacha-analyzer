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
  rust_capture.CapturedRequest? _hit;
  StreamSubscription<rust_capture.CapturedRequest>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    // 不在 dispose 呼叫 stopCapture：dispose 不能 await，且若 page 重建時 Rust session
    // 殘留，main.dart 啟動時會用 cleanupStaleProxy 兜底還原系統 proxy。
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
        setState(() {
          _hit = null;
          _capturing = true;
        });
        final stream = rust_capture.startCapture();
        _sub = stream.listen(
          (event) {
            if (!mounted) return;
            setState(() => _hit = event);
            // 不在這裡改 _capturing：Rust 端命中後 sink 會 close → onDone 統一處理。
            // 兩端各自設 _capturing 會造成 button 與 stream 狀態不一致。
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _error = '$e');
            // 依 spec §6.4：FRB 的 RustStreamSink 在 error 後會 close sink，onDone 會接著來。
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              _capturing = false;
              _sub = null;
            });
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _capturing = false;
      });
    }
  }

  Widget _buildBody() {
    if (_hit != null) {
      return _HitCard(captured: _hit!);
    }
    if (_capturing) {
      return const _WaitingIndicator();
    }
    return const Center(child: Text('尚未開始攔截'));
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
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

class _WaitingIndicator extends StatelessWidget {
  const _WaitingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('等待 getGachaLog 請求…'),
        ],
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.captured});

  final rust_capture.CapturedRequest captured;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '✅ 已取得 getGachaLog URL，攔截已停止',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Method: ${captured.method}'),
              Text('Host: ${captured.host}'),
              const SizedBox(height: 8),
              SelectableText(
                captured.url,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
