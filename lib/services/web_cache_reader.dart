import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 同步讀整個檔案的函式，檔案不存在丟 [FileSystemException]（可注入以利測試）。
typedef CacheFileReader = Uint8List Function(String path);

/// 以共享讀寫刪除模式讀取整個檔案，遊戲執行中持有 `data_2` 時也能讀。
Uint8List readSharedFile(String path) {
  final pathPtr = path.toNativeUtf16();
  final sizePtr = calloc<Int64>();
  final readPtr = calloc<Uint32>();
  try {
    final handle = CreateFile(
      pathPtr,
      GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      NULL,
    );
    if (handle == INVALID_HANDLE_VALUE) {
      throw FileSystemException(
        'Cannot open file',
        path,
        OSError('', GetLastError()),
      );
    }
    try {
      if (GetFileSizeEx(handle, sizePtr) == 0) {
        throw FileSystemException(
          'Cannot get file size',
          path,
          OSError('', GetLastError()),
        );
      }
      final size = sizePtr.value;
      final buffer = calloc<Uint8>(size == 0 ? 1 : size);
      try {
        var total = 0;
        while (total < size) {
          if (ReadFile(
                handle,
                buffer + total,
                size - total,
                readPtr,
                nullptr,
              ) ==
              0) {
            throw FileSystemException(
              'Cannot read file',
              path,
              OSError('', GetLastError()),
            );
          }
          if (readPtr.value == 0) break;
          total += readPtr.value;
        }
        return Uint8List.fromList(buffer.asTypedList(total));
      } finally {
        calloc.free(buffer);
      }
    } finally {
      CloseHandle(handle);
    }
  } finally {
    calloc.free(pathPtr);
    calloc.free(sizePtr);
    calloc.free(readPtr);
  }
}
