import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/lang_catalog.dart';

/// 轉換引擎 provider；接 [LangCatalogService.ensure] 作為名冊解析器。
final gachaLanguageConverterProvider = Provider<GachaLanguageConverter>((ref) {
  final service = ref.read(langCatalogServiceProvider);
  return GachaLanguageConverter(ensureCatalog: service.ensure);
});
