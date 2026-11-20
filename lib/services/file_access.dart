import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 檔案存取（存檔／分享／剪貼簿／選檔）流程的 logger。
final _log = Logger('io.file');

/// 存檔結果：[displayName] 給成功訊息顯示；[path] 只在桌面有值。
class SavedFile {
  /// 建立存檔結果。
  const SavedFile({required this.displayName, this.path});

  /// 顯示給使用者看的檔名。
  final String displayName;

  /// 桌面的實際檔案路徑；Android 為 null。
  final String? path;
}

/// 開啟系統存檔對話框並寫入 bytes，回傳 file_picker 給的原始字串（取消為 null）。
typedef FileSaveDialog =
    Future<String?> Function(
      Uint8List bytes,
      String suggestedName,
      String extension,
      String mimeType,
      String? dialogTitle,
    );

/// 開啟系統選檔對話框並回傳檔案內容（取消為 null）。
typedef FileOpenDialog =
    Future<Uint8List?> Function(List<String>? extensions, String? dialogTitle);

/// 開啟系統選資料夾對話框並回傳路徑（取消為 null）。
typedef DirectoryDialog = Future<String?> Function(String? dialogTitle);

/// 以系統分享面板分享 bytes。
typedef FileSharer =
    Future<void> Function(Uint8List bytes, String fileName, String mimeType);

/// 把圖片寫入系統剪貼簿（[isGif] 選 GIF／PNG；[filePath] 供 GIF 掛實體檔路徑），回傳是否成功。
typedef ImageClipboardWriter =
    Future<bool> Function(
      Uint8List bytes, {
      required bool isGif,
      String? filePath,
    });

/// 預設存檔對話框：桌面回傳選擇路徑；Android 回傳 content Uri 去掉 scheme 的路徑
/// （如 `/document/primary:Download/a.json`）。
Future<String?> _defaultSaveDialog(
  Uint8List bytes,
  String suggestedName,
  String extension,
  String mimeType,
  String? dialogTitle,
) => FilePicker.saveFile(
  dialogTitle: dialogTitle,
  fileName: suggestedName,
  bytes: bytes,
  type: FileType.custom,
  allowedExtensions: [extension],
  lockParentWindow: true,
);

/// 預設選檔對話框；拿不到 bytes 時退回讀 path。
Future<Uint8List?> _defaultOpenDialog(
  List<String>? extensions,
  String? dialogTitle,
) async {
  final result = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
    withData: true,
    lockParentWindow: true,
  );
  final file = result?.files.single;
  if (file == null) return null;
  final path = file.path;
  final bytes =
      file.bytes ?? (path == null ? null : await File(path).readAsBytes());
  await _clearPickerCache();
  return bytes;
}

/// 清掉 Android 上 file_picker 複製進 cache 的選檔殘留（即使 withData 也會複製）。
///
/// 只在 Android 呼叫：其他平台的 platform 預設實作會丟 UnimplementedError。失敗只記 warning。
Future<void> _clearPickerCache() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await FilePicker.clearTemporaryFiles();
  } catch (e, st) {
    _log.warning('clear picker cache failed', e, st);
  }
}

/// 預設選資料夾對話框。
Future<String?> _defaultDirectoryDialog(String? dialogTitle) =>
    FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
      lockParentWindow: true,
    );

/// 把分享用檔案寫到 [tempRoot]`/share_out/`[fileName]，先刪掉上一次的目錄，
/// 讓暫存目錄最多只殘留一個分享檔（`XFile.fromData` 的副本不會被清掉）。
@visibleForTesting
Future<File> prepareShareFile(
  Directory tempRoot,
  Uint8List bytes,
  String fileName,
) async {
  final dir = Directory('${tempRoot.path}${Platform.pathSeparator}share_out');
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  return File(
    '${dir.path}${Platform.pathSeparator}$fileName',
  ).writeAsBytes(bytes);
}

/// 預設分享：寫成暫存檔後交給 share_plus。
Future<void> _defaultSharer(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  final file = await prepareShareFile(
    await getTemporaryDirectory(),
    bytes,
    fileName,
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      fileNameOverrides: [fileName],
    ),
  );
}

/// 預設剪貼簿寫入：寫圖片 [bytes] 到系統剪貼簿，[isGif] 決定用 GIF 或 PNG 格式。
/// GIF 且有 [filePath] 時，額外掛上實體檔路徑（Windows 為 `CF_HDROP`），讓以
/// 「檔案」貼上的目標（Discord、檔案總管、聊天軟體）取得真正的 `.gif` 檔以保留
/// 動畫；放最前面提高優先序。純圖片貼上的目標（小畫家等）仍只會拿到系統合成的
/// 靜態點陣圖 — 這是 Windows 剪貼簿圖片模型的限制，無法避免。回是否成功（平台
/// 不支援回 false）。
Future<bool> _defaultClipboardWriter(
  Uint8List bytes, {
  required bool isGif,
  String? filePath,
}) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final item = DataWriterItem(suggestedName: isGif ? 'image.gif' : 'image.png');
  if (isGif && filePath != null) {
    item.add(Formats.fileUri(Uri.file(filePath)));
  }
  item.add(isGif ? Formats.gif(bytes) : Formats.png(bytes));
  await clipboard.write([item]);
  return true;
}

/// 存檔對話框 seam，讓測試不開真實對話框。
@visibleForTesting
FileSaveDialog fileSaveDialog = _defaultSaveDialog;

/// 選檔對話框 seam。
@visibleForTesting
FileOpenDialog fileOpenDialog = _defaultOpenDialog;

/// 選資料夾對話框 seam。
@visibleForTesting
DirectoryDialog directoryDialog = _defaultDirectoryDialog;

/// 分享 seam。
@visibleForTesting
FileSharer fileSharer = _defaultSharer;

/// 圖片剪貼簿寫入 seam。
@visibleForTesting
ImageClipboardWriter imageClipboardWriter = _defaultClipboardWriter;

/// 將所有 seam 重設為預設實作，供 tearDown 使用。
@visibleForTesting
void resetFileAccessSeams() {
  fileSaveDialog = _defaultSaveDialog;
  fileOpenDialog = _defaultOpenDialog;
  directoryDialog = _defaultDirectoryDialog;
  fileSharer = _defaultSharer;
  imageClipboardWriter = _defaultClipboardWriter;
}

/// 讓使用者選位置存檔。取消回 null；寫入失敗記 severe 後 rethrow。
///
/// 呼叫端須先把 `suggestedName` 內的 `<>:"/\|?*` 換成 `_`，因為 Windows 上的 file_picker 會在 isolate 內丟例外，導致 await 永遠不會完成。
Future<SavedFile?> saveBytes(
  Uint8List bytes, {
  required String suggestedName,
  required String extension,
  required String mimeType,
  String? dialogTitle,
}) async {
  final String? saved;
  try {
    saved = await fileSaveDialog(
      bytes,
      suggestedName,
      extension,
      mimeType,
      dialogTitle,
    );
  } catch (e, st) {
    _log.severe('save failed name=$suggestedName mime=$mimeType', e, st);
    rethrow;
  }
  if (saved == null) {
    _log.info('save cancelled name=$suggestedName');
    return null;
  }
  // 服務層沒有 Riverpod ref，無法讀 isAndroidProvider；兩者在正式環境一致。
  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final displayName = isAndroid
      ? displayNameForSavedPath(
          saved,
          suggestedName: suggestedName,
          extension: extension,
        )
      : _baseName(saved);
  _log.info(
    'save ok name=$displayName ${isAndroid ? '' : 'path=${sanitizeFsPath(saved)} '}bytes=${bytes.length}',
  );
  return SavedFile(displayName: displayName, path: isAndroid ? null : saved);
}

/// 取路徑最後一個分隔符之後的檔名。
String _baseName(String path) =>
    path.substring(path.lastIndexOf(RegExp(r'[/\\]')) + 1);

/// 從 Android 存檔結果字串取出顯示檔名（最後一個分隔符之後）；副檔名不符
/// （如 Downloads provider 的 `/document/msf:1234`）時退回 [suggestedName]。
String displayNameForSavedPath(
  String saved, {
  required String suggestedName,
  required String extension,
}) {
  final name = _baseName(saved);
  return name.toLowerCase().endsWith('.${extension.toLowerCase()}')
      ? name
      : suggestedName;
}

/// 以系統分享面板分享 bytes；使用者關掉面板也算成功，例外記 warning 回 false。
Future<bool> shareBytes(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  try {
    await fileSharer(bytes, fileName, mimeType);
    _log.info('share ok name=$fileName mime=$mimeType bytes=${bytes.length}');
    return true;
  } catch (e, st) {
    _log.warning('share failed name=$fileName mime=$mimeType', e, st);
    return false;
  }
}

/// 把圖片寫入系統剪貼簿（[isGif] 選 GIF／PNG；[filePath] 供電腦版 GIF 掛實體檔路徑）。
/// 成功回 true；平台不支援回 false；例外記 warning 後回 false。
Future<bool> copyImageToClipboard(
  Uint8List bytes, {
  bool isGif = false,
  String? filePath,
}) async {
  try {
    final ok = await imageClipboardWriter(
      bytes,
      isGif: isGif,
      // App 私有目錄的路徑其他 App 讀不到，Android 只放 bytes。
      filePath: defaultTargetPlatform == TargetPlatform.android
          ? null
          : filePath,
    );
    _log.info('copy image clipboard=$ok gif=$isGif bytes=${bytes.length}');
    return ok;
  } catch (e, st) {
    _log.warning('copy image failed', e, st);
    return false;
  }
}

/// 讓使用者選檔並回傳內容；取消回 null。
Future<Uint8List?> pickFileBytes({
  List<String>? extensions,
  String? dialogTitle,
}) async {
  final bytes = await fileOpenDialog(extensions, dialogTitle);
  _log.info(
    bytes == null
        ? 'pick file cancelled'
        : 'pick file ok bytes=${bytes.length}',
  );
  return bytes;
}

/// 讓使用者選文字檔並以 UTF-8 解碼；取消回 null，不合法 UTF-8 丟 [FormatException]。
Future<String?> pickTextFile({
  required List<String> extensions,
  String? dialogTitle,
}) async {
  final bytes = await pickFileBytes(
    extensions: extensions,
    dialogTitle: dialogTitle,
  );
  if (bytes == null) return null;
  try {
    return utf8.decode(bytes);
  } on FormatException catch (e, st) {
    _log.warning(
      'pick text file is not valid utf-8 bytes=${bytes.length}',
      e,
      st,
    );
    rethrow;
  }
}

/// 讓使用者選資料夾；取消回 null。
Future<String?> pickDirectory({String? dialogTitle}) async {
  final path = await directoryDialog(dialogTitle);
  _log.info(
    path == null
        ? 'pick directory cancelled'
        : 'pick directory ok path=${sanitizeFsPath(path)}',
  );
  return path;
}
