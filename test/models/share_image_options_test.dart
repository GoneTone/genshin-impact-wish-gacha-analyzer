import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';

void main() {
  test('預設：深色 + 不顯示完整 UID', () {
    const o = ShareImageOptions();
    expect(o.brightness, Brightness.dark);
    expect(o.showFullUid, isFalse);
  });

  test('可指定 brightness 與 showFullUid', () {
    const o = ShareImageOptions(
      brightness: Brightness.light,
      showFullUid: true,
    );
    expect(o.brightness, Brightness.light);
    expect(o.showFullUid, isTrue);
  });
}
