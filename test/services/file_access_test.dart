import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';

void main() {
  tearDown(() {
    resetFileAccessSeams();
    debugDefaultTargetPlatformOverride = null;
  });

  final bytes = Uint8List.fromList([1, 2, 3]);

  Future<SavedFile?> save() => saveBytes(
    bytes,
    suggestedName: 'genshin.json',
    extension: 'json',
    mimeType: 'application/json',
  );

  test('saveBytes returns null when the user cancels', () async {
    fileSaveDialog = (_, _, _, _, _) async => null;
    expect(await save(), isNull);
  });

  test('saveBytes on desktop returns the file path and its basename', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    fileSaveDialog = (_, _, _, _, _) async => r'C:\tmp\a.json';
    final saved = await save();
    expect(saved!.path, r'C:\tmp\a.json');
    expect(saved.displayName, 'a.json');
  });

  test(
    'saveBytes on desktop keeps the basename even with another extension',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      fileSaveDialog = (_, _, _, _, _) async => r'C:\tmp\a.txt';
      final saved = await save();
      expect(saved!.path, r'C:\tmp\a.txt');
      expect(saved.displayName, 'a.txt');
    },
  );

  test('saveBytes on Android returns no path', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    fileSaveDialog = (_, _, _, _, _) async =>
        '/document/primary:Download/a.json';
    final saved = await save();
    expect(saved!.path, isNull);
    expect(saved.displayName, 'a.json');
  });

  test(
    'saveBytes on Android falls back to the suggested name for opaque ids',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fileSaveDialog = (_, _, _, _, _) async => '/document/msf:1234';
      final saved = await save();
      expect(saved!.path, isNull);
      expect(saved.displayName, 'genshin.json');
    },
  );

  test('saveBytes passes the dialog title through', () async {
    String? title;
    fileSaveDialog = (_, _, _, _, t) async {
      title = t;
      return null;
    };
    await saveBytes(
      bytes,
      suggestedName: 'a.json',
      extension: 'json',
      mimeType: 'application/json',
      dialogTitle: '儲存',
    );
    expect(title, '儲存');
  });

  test(
    'displayNameForSavedPath falls back when the extension does not match',
    () {
      expect(
        displayNameForSavedPath(
          '/document/primary:Download/a.txt',
          suggestedName: 'genshin.json',
          extension: 'json',
        ),
        'genshin.json',
      );
    },
  );

  test('saveBytes rethrows when the dialog fails', () async {
    fileSaveDialog = (_, _, _, _, _) async => throw StateError('boom');
    await expectLater(save(), throwsStateError);
  });

  test('shareBytes passes the name and mime type and returns true', () async {
    String? name;
    String? mime;
    fileSharer = (_, n, m) async {
      name = n;
      mime = m;
    };
    expect(
      await shareBytes(bytes, fileName: 'a.png', mimeType: 'image/png'),
      isTrue,
    );
    expect(name, 'a.png');
    expect(mime, 'image/png');
  });

  test('shareBytes returns false when sharing throws', () async {
    fileSharer = (_, _, _) async => throw StateError('boom');
    expect(
      await shareBytes(bytes, fileName: 'a.png', mimeType: 'image/png'),
      isFalse,
    );
  });

  test('pickTextFile decodes UTF-8 Chinese text', () async {
    fileOpenDialog = (_, _) async =>
        Uint8List.fromList(utf8.encode('{"alias":"主號"}'));
    expect(await pickTextFile(extensions: ['json']), '{"alias":"主號"}');
  });

  test('pickTextFile throws FormatException on invalid UTF-8', () async {
    fileOpenDialog = (_, _) async => Uint8List.fromList([0xff, 0xfe, 0x00]);
    await expectLater(
      pickTextFile(extensions: ['json']),
      throwsFormatException,
    );
  });

  test('pickTextFile returns null when cancelled', () async {
    fileOpenDialog = (_, _) async => null;
    expect(await pickTextFile(extensions: ['json']), isNull);
  });

  test('copyImageToClipboard returns what the writer returns', () async {
    imageClipboardWriter = (_, {required isGif, filePath}) async => true;
    expect(await copyImageToClipboard(bytes), isTrue);
    imageClipboardWriter = (_, {required isGif, filePath}) async => false;
    expect(await copyImageToClipboard(bytes), isFalse);
  });

  test('copyImageToClipboard returns false when the writer throws', () async {
    imageClipboardWriter = (_, {required isGif, filePath}) async =>
        throw StateError('boom');
    expect(await copyImageToClipboard(bytes), isFalse);
  });

  test('copyImageToClipboard drops the file path on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    bool? gif;
    String? path = 'unset';
    imageClipboardWriter = (_, {required isGif, filePath}) async {
      gif = isGif;
      path = filePath;
      return true;
    };
    await copyImageToClipboard(bytes, isGif: true, filePath: 'C:/x.gif');
    expect(gif, isTrue);
    expect(path, isNull);
  });

  test('copyImageToClipboard keeps the file path on desktop', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    String? path;
    imageClipboardWriter = (_, {required isGif, filePath}) async {
      path = filePath;
      return true;
    };
    await copyImageToClipboard(bytes, isGif: true, filePath: 'C:/x.gif');
    expect(path, 'C:/x.gif');
  });

  test('displayNameForSavedPath falls back for a gif saved to Downloads', () {
    expect(
      displayNameForSavedPath(
        '/document/msf:1234',
        suggestedName: '胡桃_立繪.gif',
        extension: 'gif',
      ),
      '胡桃_立繪.gif',
    );
    expect(
      displayNameForSavedPath(
        '/document/primary:Download/a.gif',
        suggestedName: '胡桃_立繪.gif',
        extension: 'gif',
      ),
      'a.gif',
    );
  });

  test('pickFileBytes returns null when cancelled', () async {
    fileOpenDialog = (_, _) async => null;
    expect(await pickFileBytes(), isNull);
  });

  test('pickFileBytes returns the bytes and forwards the arguments', () async {
    List<String>? exts;
    String? title;
    fileOpenDialog = (e, t) async {
      exts = e;
      title = t;
      return bytes;
    };
    expect(await pickFileBytes(extensions: ['json'], dialogTitle: '開啟'), bytes);
    expect(exts, ['json']);
    expect(title, '開啟');
  });

  test('pickDirectory returns null when cancelled', () async {
    directoryDialog = (_) async => null;
    expect(await pickDirectory(), isNull);
  });

  test('pickDirectory returns the path and forwards the title', () async {
    String? title;
    directoryDialog = (t) async {
      title = t;
      return r'C:\games';
    };
    expect(await pickDirectory(dialogTitle: '選取資料夾'), r'C:\games');
    expect(title, '選取資料夾');
  });

  group('prepareShareFile', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('share_prep_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('writes the bytes under share_out with the given name', () async {
      final file = await prepareShareFile(temp, bytes, 'a.png');
      expect(
        file.path,
        '${temp.path}${Platform.pathSeparator}share_out'
        '${Platform.pathSeparator}a.png',
      );
      expect(file.readAsBytesSync(), bytes);
    });

    test('removes the previously prepared file', () async {
      final first = await prepareShareFile(temp, bytes, 'a.png');
      final second = await prepareShareFile(temp, bytes, 'b.png');
      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isTrue);
    });
  });

  group('default dialogs through file_picker', () {
    late _FakeFilePicker fake;

    setUp(() {
      final original = FilePickerPlatform.instance;
      fake = _FakeFilePicker();
      FilePickerPlatform.instance = fake;
      addTearDown(() => FilePickerPlatform.instance = original);
    });

    test('save dialog locks the parent window and passes the title', () async {
      await saveBytes(
        bytes,
        suggestedName: 'a.json',
        extension: 'json',
        mimeType: 'application/json',
        dialogTitle: '另存新檔',
      );
      expect(fake.lockParentWindow['save'], isTrue);
      expect(fake.titles['save'], '另存新檔');
    });

    test('open dialog locks the parent window and passes the title', () async {
      await pickFileBytes(extensions: ['json'], dialogTitle: '開啟');
      expect(fake.lockParentWindow['pick'], isTrue);
      expect(fake.titles['pick'], '開啟');
    });

    test('pickTextFile forwards the title', () async {
      await pickTextFile(extensions: ['json'], dialogTitle: '開啟');
      expect(fake.titles['pick'], '開啟');
    });

    test(
      'folder dialog locks the parent window and passes the title',
      () async {
        await pickDirectory(dialogTitle: '選取資料夾');
        expect(fake.lockParentWindow['dir'], isTrue);
        expect(fake.titles['dir'], '選取資料夾');
      },
    );

    test(
      'Android clears the picker cache after reading the picked file',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        fake.pickedBytes = Uint8List.fromList([9]);
        expect(await pickFileBytes(), Uint8List.fromList([9]));
        expect(fake.cleared, 1);
      },
    );

    test(
      'Android keeps the picked bytes when clearing the cache fails',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        fake.pickedBytes = Uint8List.fromList([9]);
        fake.clearThrows = true;
        expect(await pickFileBytes(), Uint8List.fromList([9]));
      },
    );

    test('desktop never clears the picker cache', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      fake.pickedBytes = Uint8List.fromList([9]);
      await pickFileBytes();
      expect(fake.cleared, 0);
    });
  });
}

/// 記錄 file_picker 收到的參數的替身平台實作。
class _FakeFilePicker extends FilePickerPlatform {
  /// 各對話框收到的 lockParentWindow。
  final lockParentWindow = <String, bool>{};

  /// 各對話框收到的標題。
  final titles = <String, String?>{};

  /// pickFiles 要回傳的檔案內容；null 表示取消。
  Uint8List? pickedBytes;

  /// clearTemporaryFiles 被呼叫的次數。
  int cleared = 0;

  /// clearTemporaryFiles 是否要丟例外。
  bool clearThrows = false;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.lockParentWindow['save'] = lockParentWindow;
    titles['save'] = dialogTitle;
    return null;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    this.lockParentWindow['pick'] = lockParentWindow;
    titles['pick'] = dialogTitle;
    final data = pickedBytes;
    if (data == null) return null;
    return FilePickerResult([
      PlatformFile(name: 'x.json', size: data.length, bytes: data),
    ]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    this.lockParentWindow['dir'] = lockParentWindow;
    titles['dir'] = dialogTitle;
    return null;
  }

  @override
  Future<bool?> clearTemporaryFiles() async {
    cleared++;
    if (clearThrows) throw StateError('boom');
    return true;
  }
}
