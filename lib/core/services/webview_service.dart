import 'package:purevideo/core/utils/safe_cookie.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:purevideo/core/utils/global_context.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewService {
  static String cleanUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static bool _uaInitialized = false;

  static Future<String> ensureCleanUserAgent() async {
    if (_uaInitialized) return cleanUserAgent;
    try {
      final defaultUa = await InAppWebViewController.getDefaultUserAgent();
      if (defaultUa.isNotEmpty) {
        cleanUserAgent = defaultUa
            .replaceAll('; wv)', ')')
            .replaceAll('; wv;', ';')
            .replaceAll(RegExp(r'Version/\d+\.\d+\s*'), '')
            .trim();
        _uaInitialized = true;
      }
    } catch (_) {}
    return cleanUserAgent;
  }

  String _buildEkinoGateUnlockJs(String targetGateUrl) {
    final safeUrl = targetGateUrl.replaceAll("'", r"\'");
    return '''
      (function() {
        if (window._ekinoUnlockStarted) return;
        window._ekinoUnlockStarted = true;
        var targetUrl = '$safeUrl';
        try {
          var u = new URL(targetUrl);
          history.replaceState(null, '', u.pathname + u.search);
        } catch (e) {}

        document.body.style.cssText = 'margin:0;padding:0;background:#0f172a;color:#f8fafc;font-family:sans-serif;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;';
        document.body.innerHTML = '<div style="text-align:center;padding:24px;max-width:360px;"><div id="pv-status" style="margin-bottom:16px;font-size:14px;color:#cbd5e1;">Weryfikacja zabezpieczeń Ekino.ws...</div><div id="gcaptcha" style="display:flex;justify-content:center;min-height:70px;"></div></div>';

        function extractAndFinish(html) {
          if (!html) return false;
          var m = html.match(/<a[^>]+class=["'][^"']*buttonprch[^"']*["'][^>]*>/i) ||
                  html.match(/<a[^>]+href=["'][^"']*play\\.ekino[^"']*["'][^>]*>/i);
          if (m && m[0]) {
            var st = document.getElementById('pv-status');
            if (st) st.textContent = 'Zweryfikowano! Otwieranie odtwarzacza...';
            window.flutter_inappwebview.callHandler('messageHandler', m[0]);
            return true;
          }
          return false;
        }

        function pvRetry() {
          window._ekinoRetries = (window._ekinoRetries || 0) + 1;
          if (window._ekinoRetries > 3) {
            var s0 = document.getElementById('pv-status');
            if (s0) s0.textContent = 'Weryfikacja nieudana. Okno zamknie sie automatycznie.';
            setTimeout(function() { window.flutter_inappwebview.callHandler('messageHandler', ''); }, 1500);
            return;
          }
          setTimeout(function() { try { window.turnstile.reset(); } catch (e) {} }, 1200);
        }

        function renderTurnstileWidget() {
          if (window._ekinoWidgetRendered) return;
          if (typeof window.turnstile === 'undefined' || !window.turnstile.render) return;
          window._ekinoWidgetRendered = true;
          var st = document.getElementById('pv-status');
          if (st) st.textContent = 'Potwierdź zabezpieczenie Cloudflare:';
          window.turnstile.render('#gcaptcha', {
            sitekey: '0x4AAAAAAAFuHEOflkh2qqPw',
            theme: 'dark',
            callback: function(token) {
              var st2 = document.getElementById('pv-status');
              if (st2) st2.textContent = 'Odblokowywanie odtwarzacza...';
              fetch('/watch/verify.php', {
                method: 'POST',
                credentials: 'include',
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                  'X-Requested-With': 'XMLHttpRequest'
                },
                body: 'verify=' + encodeURIComponent(token)
              })
              .then(function() {
                return fetch(targetUrl, {
                  method: 'GET',
                  credentials: 'include',
                  cache: 'no-store'
                });
              })
              .then(function(r) { return r.text(); })
              .then(function(html) {
                if (!extractAndFinish(html)) {
                  if (st2) st2.textContent = 'Ponawianie weryfikacji...';
                  pvRetry();
                }
              })
              .catch(function() {
                pvRetry();
              });
            }
          });
        }

        window.onEkinoTurnstileLoad = function() {
          renderTurnstileWidget();
        };

        fetch(targetUrl, {
          method: 'GET',
          credentials: 'include',
          cache: 'no-store'
        })
        .then(function(r) { return r.text(); })
        .then(function(html) {
          if (extractAndFinish(html)) return;
          var s = document.createElement('script');
          s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onEkinoTurnstileLoad&render=explicit';
          s.async = true;
          s.defer = true;
          document.head.appendChild(s);
        })
        .catch(function() {
          var s = document.createElement('script');
          s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onEkinoTurnstileLoad&render=explicit';
          s.async = true;
          s.defer = true;
          document.head.appendChild(s);
        });
      })();
    ''';
  }

  String _getJsCodeForElement(String elementSelector) {
    return '''
      (function() {
        function waitForElement(selector, callback) {
          const element = document.querySelector(selector);
          if (element) {
            callback(element);
          } else {
            setTimeout(() => waitForElement(selector, callback), 200);
          }
        }
        waitForElement('$elementSelector', function(element) {
          window.flutter_inappwebview.callHandler('messageHandler', element.outerHTML);
        });
      })();
    ''';
  }

  Future<dom.Element?> waitForDomElement(
      String url, String elementSelector) async {
    await ensureCleanUserAgent();
    final completer = Completer<dom.Element?>();
    executeJavaScript(url, _getJsCodeForElement(elementSelector),
            timeoutSeconds: 22)
        .then((result) {
      if (result != null && result.trim().isNotEmpty) {
        final document = dom.Document.html(result);
        final element = document.querySelector(elementSelector) ??
            document.querySelector('a');
        if (!completer.isCompleted) completer.complete(element);
      } else {
        if (!completer.isCompleted) completer.complete(null);
      }
    }).catchError((error) {
      debugPrint('Error waiting for DOM element: $error');
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  Future<String?> executeJavaScript(String url, String jsCode,
      {int timeoutSeconds = 90}) async {
    await ensureCleanUserAgent();
    final completer = Completer<String?>();
    BuildContext? dialogCtx;
    final timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        if (dialogCtx != null && dialogCtx!.mounted) {
          Navigator.of(dialogCtx!).pop();
        }
      }
    });
    showDialog(
      context: getIt<GlobalContext>().context,
      barrierDismissible: true,
      builder: (context) {
        dialogCtx = context;
        return _buildWebViewDialog(context, url, jsCode, completer);
      },
    ).then((_) {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });
    return completer.future;
  }

  Future<List<io.Cookie>?> getCfCookies(String url,
      {List<io.Cookie>? initialCookies}) async {
    await ensureCleanUserAgent();
    final completer = Completer<List<io.Cookie>?>();
    BuildContext? dialogCtx;
    final timer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        if (dialogCtx != null && dialogCtx!.mounted) {
          Navigator.of(dialogCtx!).pop();
        }
      }
    });
    showDialog(
      context: getIt<GlobalContext>().context,
      builder: (context) {
        dialogCtx = context;
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(url)),
              initialSettings: InAppWebViewSettings(
                userAgent: cleanUserAgent,
                transparentBackground: true,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                clearCache: false,
                cacheEnabled: true,
                incognito: false,
                useShouldInterceptRequest: false,
              ),
              onWebViewCreated: (controller) async {
                if (initialCookies != null && initialCookies.isNotEmpty) {
                  for (io.Cookie cookie in initialCookies) {
                    await CookieManager.instance().setCookie(
                      name: cookie.name,
                      url: WebUri(url),
                      value: cookie.value,
                    );
                  }
                }
              },
              onLoadStop: (controller, loadedUrl) async {
                try {
                  if (loadedUrl == null) return;
                  final cookies = await CookieManager.instance()
                      .getCookies(url: loadedUrl);
                  final cfClearance = cookies
                      .firstWhereOrNull((c) => c.name == 'cf_clearance');
                  if (cfClearance != null && !completer.isCompleted) {
                    timer.cancel();
                    completer.complete(cookies
                        .map((c) => RawCookie(c.name, c.value))
                        .toList());
                    if (context.mounted) Navigator.of(context).pop();
                  }
                } catch (_) {
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
          ),
        );
      },
    ).then((_) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  Widget _buildWebViewDialog(BuildContext context, String url, String jsCode,
      Completer<String?> completer) {
    final isLogin = url.contains('logowanie') || url.contains('login');
    final isEkinoGate = url.contains('ekino.ws/watch/f/');
    final initialLoadUrl =
        isEkinoGate ? 'https://ekino.ws/watch/verify.php' : url;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                color: const Color(0xFF1E293B),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        if (!completer.isCompleted) {
                          completer.complete(isLogin
                              ? '{"success":false,"error":"Anulowano logowanie"}'
                              : null);
                        }
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    Expanded(
                      child: Text(
                        isLogin
                            ? 'Potwierdź Captcha i kliknij Zaloguj'
                            : 'Weryfikacja zabezpieczeń (lub kliknij X aby pominąć)',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(initialLoadUrl),
                  headers: url.contains('ekino.ws')
                      ? const {'Referer': 'https://ekino.ws/'}
                      : null,
                ),
                initialSettings: InAppWebViewSettings(
                  userAgent: cleanUserAgent,
                  transparentBackground: false,
                  supportZoom: true,
                  disableContextMenu: false,
                  disableHorizontalScroll: false,
                  disableVerticalScroll: false,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  clearCache: false,
                  cacheEnabled: true,
                  incognito: false,
                  thirdPartyCookiesEnabled: true,
                  useShouldInterceptRequest: false,
                ),
                onWebViewCreated: (controller) async {
                  controller.addJavaScriptHandler(
                    handlerName: 'messageHandler',
                    callback: (message) async {
                      if (message.isNotEmpty && message[0] != null) {
                        var msgStr = message[0].toString();
                        if (msgStr.contains('"success":true') ||
                            msgStr.contains('"success": true')) {
                          try {
                            final origin = Uri.parse(url).origin;
                            final allCookies = await CookieManager.instance()
                                .getCookies(url: WebUri(origin));
                            if (allCookies.isNotEmpty) {
                              final cookieStr = allCookies
                                  .map((c) => '${c.name}=${c.value}')
                                  .join('; ');
                              msgStr = jsonEncode(
                                  {'success': true, 'cookies': cookieStr});
                            }
                          } catch (_) {}
                        }
                        if (!completer.isCompleted) {
                          completer.complete(
                              msgStr.trim().isEmpty ? null : msgStr);
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      } else {
                        if (!completer.isCompleted) completer.complete(null);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                  );
                },
                onLoadStop: (controller, loadedUrl) async {
                  try {
                    if (isEkinoGate) {
                      await controller.evaluateJavascript(
                          source: _buildEkinoGateUnlockJs(url));
                      return;
                    }
                    final cur = loadedUrl?.toString() ?? '';
                    if (url.contains('filman.cc/logowanie') &&
                        cur.contains('filman.cc') &&
                        !cur.contains('/logowanie') &&
                        !cur.contains('/rejestracja') &&
                        !cur.contains('/przypomnij')) {
                      final html = await controller.evaluateJavascript(
                          source: 'document.documentElement.innerHTML');
                      if (html != null &&
                          (html.toString().contains('wyloguj') ||
                              html.toString().contains('item-list'))) {
                        final allCookies = await CookieManager.instance()
                            .getCookies(url: WebUri('https://filman.cc'));
                        if (allCookies.isNotEmpty && !completer.isCompleted) {
                          final cookieStr = allCookies
                              .map((c) => '${c.name}=${c.value}')
                              .join('; ');
                          completer.complete(jsonEncode(
                              {'success': true, 'cookies': cookieStr}));
                          if (context.mounted) Navigator.of(context).pop();
                          return;
                        }
                      }
                    }
                    await controller.evaluateJavascript(source: jsCode);
                  } catch (e) {
                    debugPrint('Błąd wykonywania JavaScript: $e');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
