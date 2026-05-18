// lib/widgets/share/share_result_snackbar.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';

void showShareResultSnackBar(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  ShareExportResult r,
) {
  final String msg;
  switch (r.status) {
    case ShareExportStatus.savedAndCopied:
      msg = l.shareImageSavedAndCopied(r.path ?? '');
    case ShareExportStatus.savedOnly:
      msg = l.shareImageSavedOnly(r.path ?? '');
    case ShareExportStatus.copiedOnly:
      msg = l.shareImageCopiedOnly;
  }
  messenger.showSnackBar(SnackBar(content: Text(msg)));
  if (r.path != null) {
    revealInFileManager(r.path!);
  }
}
