import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:logging/logging.dart';

/// [linkifyHtml] 的 logger。
final Logger _log = Logger('ui.linkify');

/// 比對 `http://` 或 `https://` 開頭的裸網址（延伸到空白或 `<` 為止）。
final RegExp _urlRe = RegExp(r'https?://[^\s<]+');

/// 連結尾端要剝除的標點（半形 + 全形），避免把句末標點吃進網址。
const String _trailingPunct = '.,;:!?)]}。，！？；：）」』】';

/// 把 [html] 內的純文字 `http(s)` 裸網址包成 `<a href>`，回傳改寫後的 HTML。
///
/// 用 DOM parser 只走訪 text node：既有 `<a>` 子樹整棵略過（不產生巢狀 `<a>`），
/// 屬性值（如 `href="…"`）因非 text node 也不會被誤改。解析或序列化意外失敗時
/// 回傳原字串（裸網址維持純文字、描述區不致渲染中斷）並記 warning。純函式、無副作用。
String linkifyHtml(String html) {
  if (html.isEmpty) return html;
  try {
    final fragment = html_parser.parseFragment(html);
    _linkifyNode(fragment);
    return fragment.outerHtml;
  } catch (e, st) {
    _log.warning(
      'linkifyHtml failed (len=${html.length}); returning original',
      e,
      st,
    );
    return html;
  }
}

/// 遞迴改寫 [node] 子節點：text node 內裸網址換成 `<a>`，`<a>` 子樹略過，其餘遞迴。
void _linkifyNode(Node node) {
  for (final child in List<Node>.from(node.nodes)) {
    if (child is Text) {
      final replacements = _linkifyText(child.data);
      if (replacements == null) continue;
      final idx = node.nodes.indexOf(child);
      node.nodes.removeAt(idx);
      node.nodes.insertAll(idx, replacements);
    } else if (child is Element) {
      if (child.localName == 'a') continue;
      _linkifyNode(child);
    }
  }
}

/// 把 [text] 拆成「文字／`<a>` 連結」節點序列；若無可連結網址回 null（呼叫端略過替換）。
List<Node>? _linkifyText(String text) {
  if (!_urlRe.hasMatch(text)) return null;
  final nodes = <Node>[];
  var last = 0;
  for (final m in _urlRe.allMatches(text)) {
    var url = m.group(0)!;
    var end = m.end;
    while (url.isNotEmpty && _trailingPunct.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
      end--;
    }
    if (url.isEmpty) continue;
    if (m.start > last) nodes.add(Text(text.substring(last, m.start)));
    nodes.add(
      Element.tag('a')
        ..attributes['href'] = url
        ..append(Text(url)),
    );
    last = end;
  }
  if (nodes.isEmpty) return null;
  if (last < text.length) nodes.add(Text(text.substring(last)));
  return nodes;
}
