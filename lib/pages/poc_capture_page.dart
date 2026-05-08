import 'package:flutter/material.dart';

class PocCapturePage extends StatefulWidget {
  const PocCapturePage({super.key});

  @override
  State<PocCapturePage> createState() => _PocCapturePageState();
}

class _PocCapturePageState extends State<PocCapturePage> {
  bool _capturing = false;
  final List<String> _urls = [];

  Future<void> _toggle() async {
    setState(() => _capturing = !_capturing);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HTTPS 攔截 PoC')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _toggle,
              child: Text(_capturing ? '停止攔截' : '開始攔截'),
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
                      title: Text(
                        _urls[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
