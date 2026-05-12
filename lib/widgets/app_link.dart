import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppLink extends StatefulWidget {
  const AppLink({super.key, required this.url, required this.child});

  final String url;
  final Widget child;

  @override
  State<AppLink> createState() => _AppLinkState();
}

class _AppLinkState extends State<AppLink> {
  bool _hovering = false;

  Future<void> _handleTap() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      debugPrint('AppLink: invalid url "${widget.url}"');
      return;
    }
    await openExternalUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.primary;
    final hoverColor =
        Color.lerp(baseColor, theme.colorScheme.onSurface, 0.15) ?? baseColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: _hovering ? hoverColor : baseColor,
            decoration: TextDecoration.underline,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

Future<void> openExternalUrl(Uri uri) async {
  if (!await canLaunchUrl(uri)) {
    debugPrint('openExternalUrl: cannot launch $uri');
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
