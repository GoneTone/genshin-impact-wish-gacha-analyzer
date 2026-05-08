import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/poc_capture_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart' as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  try {
    final cleaned = await rust_capture.cleanupStaleProxy();
    if (cleaned) {
      debugPrint('[startup] stale proxy detected and reset');
    }
  } catch (e) {
    debugPrint('[startup] cleanup_stale_proxy failed: $e');
  }

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PocCapturePage());
  }
}
