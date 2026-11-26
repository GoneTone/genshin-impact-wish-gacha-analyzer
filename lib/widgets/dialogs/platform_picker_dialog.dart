import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 顯示平台選擇對話框；單選導覽式：點一列即回傳該 [PlatformImporter]，取消回 null。
Future<PlatformImporter?> showPlatformPickerDialog({
  required BuildContext context,
}) {
  return showDialog<PlatformImporter>(
    context: context,
    builder: (_) => const _PlatformPickerDialog(),
  );
}

/// 平台選擇 dialog 的實作 widget。
class _PlatformPickerDialog extends StatelessWidget {
  const _PlatformPickerDialog();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      size: AppDialogSize.sm,
      title: Text(l.platformPickerTitle),
      content: ListView(
        shrinkWrap: true,
        children: [
          for (final importer in kPlatformImporters)
            ListTile(
              leading: Image.asset(importer.iconAsset, width: 32, height: 32),
              title: Text(importer.displayName(l)),
              subtitle: switch (importer.subtitle(l)) {
                final s? => Text(s),
                _ => null,
              },
              onTap: () => Navigator.of(context).pop(importer),
            ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
          label: Text(l.actionCancel),
        ),
      ],
    );
  }
}
