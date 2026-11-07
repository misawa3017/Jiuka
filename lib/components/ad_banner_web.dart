import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  static int _nextViewId = 0;
  static final Set<String> _loadedClients = {};

  static const _client = String.fromEnvironment('ADSENSE_CLIENT_ID');
  static const _slot = String.fromEnvironment('ADSENSE_BANNER_SLOT_ID');

  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'jiuka-adsense-banner-${_nextViewId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final container = web.document.createElement('div');
      container.setAttribute('style', 'width:100%;height:100%;overflow:hidden');
      final ad = web.document.createElement('ins');
      ad.setAttribute('class', 'adsbygoogle');
      ad.setAttribute('style', 'display:block;width:100%;height:100%');
      ad.setAttribute('data-ad-client', _client);
      ad.setAttribute('data-ad-slot', _slot);
      ad.setAttribute('data-ad-format', 'auto');
      ad.setAttribute('data-full-width-responsive', 'true');
      container.append(ad);

      if (_loadedClients.add(_client)) {
        final script =
            web.document.createElement('script') as web.HTMLScriptElement;
        script.async = true;
        script.crossOrigin = 'anonymous';
        script.src =
            'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=$_client';
        web.document.head?.append(script);
      }

      final request =
          web.document.createElement('script') as web.HTMLScriptElement;
      request.text =
          '(window.adsbygoogle = window.adsbygoogle || []).push({});';
      web.document.head?.append(request);
      return container;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_client.startsWith('ca-pub-') || _slot.isEmpty) {
      return const SizedBox.shrink();
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 728),
        child: SizedBox(
          width: double.infinity,
          height: 120,
          child: HtmlElementView(viewType: _viewType),
        ),
      ),
    );
  }
}
