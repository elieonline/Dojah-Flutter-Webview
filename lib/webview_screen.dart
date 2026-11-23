// ignore_for_file: deprecated_member_use

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

class DojahKYC {
  final String appId;
  final String publicKey;
  final String type;
  final int? amount;
  final String? referenceId;
  final Map<String, dynamic>? userData;
  final Map<String, dynamic>? metaData;
  final Map<String, dynamic>? govData;
  final Map<String, dynamic>? govId;
  final Map<String, dynamic>? config;
  final Function(dynamic)? onCloseCallback;

  DojahKYC({
    required this.appId,
    required this.publicKey,
    required this.type,
    this.userData,
    this.config,
    this.metaData,
    this.govData,
    this.govId,
    this.amount,
    this.referenceId,
    this.onCloseCallback,
  });

  Future<void> open(BuildContext context,
      {Function(dynamic result)? onSuccess,
      Function(dynamic close)? onClose,
      Function(dynamic error)? onError}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebviewScreen(
          appId: appId,
          publicKey: publicKey,
          type: type,
          userData: userData,
          metaData: metaData,
          govData: govData,
          govId: govId,
          config: config,
          amount: amount,
          referenceId: referenceId,
          success: (result) {
            onSuccess!(result);
          },
          close: (close) {
            onClose!(close);
          },
          error: (error) {
            onError!(error);
          },
        ),
      ),
    );
  }
}

class WebviewScreen extends StatefulWidget {
  final String appId;
  final String publicKey;
  final String type;
  final int? amount;
  final String? referenceId;
  final Map<String, dynamic>? userData;
  final Map<String, dynamic>? metaData;
  final Map<String, dynamic>? govData;
  final Map<String, dynamic>? govId;
  final Map<String, dynamic>? config;
  final Widget Function(Widget child)? builder;
  final Function(dynamic) success;
  final Function(dynamic) error;
  final Function(dynamic) close;
  const WebviewScreen({
    Key? key,
    required this.appId,
    required this.publicKey,
    required this.type,
    this.userData,
    this.metaData,
    this.govData,
    this.govId,
    this.config,
    this.amount,
    this.referenceId,
    this.builder,
    required this.success,
    required this.error,
    required this.close,
  }) : super(key: key);

  @override
  State<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends State<WebviewScreen> {
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers = {
    Factory(() => EagerGestureRecognizer())
  };
  final GlobalKey webViewKey = GlobalKey();
  late InAppWebViewController _webViewController;
  double progress = 0;
  String url = '';
  late PullToRefreshController pullToRefreshController;

  InAppWebViewSettings options = InAppWebViewSettings(
    allowsInlineMediaPlayback: true,
    cacheEnabled: false, // Disable cache
    clearCache: true, // Clear cache
    verticalScrollBarEnabled: true,
    horizontalScrollBarEnabled: true, // Enable horizontal scrollbar
    supportZoom: true, // Allow zooming (optional)
    builtInZoomControls: true, // Enable built-in zoom controls
    displayZoomControls: false, // Hide display of zoom controls
    disableHorizontalScroll: false, // Ensure horizontal scrolling is not disabled
    disableVerticalScroll: false, // Ensure vertical scrolling is not disabled
    transparentBackground: false, // Default background for visibility
    javaScriptEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    useHybridComposition: true,
    // Applied to iframes created by the Android webview, including identity.dojah.io.
    iframeAllow: "camera; microphone; geolocation; fullscreen",
    iframeAllowFullscreen: true,
  );

  bool isGranted = false;
  bool isLocationGranted = false;

  bool isLocationPermissionGranted = false;
  dynamic locationData;
  dynamic timeZone;
  dynamic zoneOffset;
  dynamic locationObject;

  @override
  void initState() {
    super.initState();
    getPermissions();
    pullToRefreshController = PullToRefreshController(
      //settings: PullToRefreshSettings(color: Colors.blue),
      onRefresh: () async {
        if (Platform.isAndroid) {
          _webViewController.reload();
        } else if (Platform.isIOS) {
          _webViewController.loadUrl(
            urlRequest: URLRequest(url: await _webViewController.getUrl()),
          );
        }
      },
    );
  }

  Future getPermissions() async {
    await initPermissions();
  }

  Future initPermissions() async {
    // The identity iframe calls getUserMedia with camera and microphone.
    // Camera access alone still fails the capture when the microphone is denied.
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final cameraStatus = statuses[Permission.camera];
    if (cameraStatus != null && cameraStatus.isPermanentlyDenied) {
      await openAppSettings();
    }

    if (!mounted) return;
    setState(() {
      isGranted = cameraStatus?.isGranted ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Builder(
      builder: (_) {
        if (!isGranted) {
          return const Center(child: CircularProgressIndicator());
        }

        return InAppWebView(
          key: webViewKey,
          gestureRecognizers: gestureRecognizers,
          initialSettings: options,
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: """
                (function () {
                  var allow = 'camera; microphone; geolocation; fullscreen';
                  function patch(iframe) {
                    if (!iframe || iframe.tagName !== 'IFRAME') return;
                    var current = iframe.getAttribute('allow') || '';
                    if (current.indexOf('camera') !== -1) return;
                    iframe.setAttribute('allow', current ? current + '; ' + allow : allow);
                  }
                  function scan(root) {
                    if (!root || !root.querySelectorAll) return;
                    var frames = root.querySelectorAll('iframe');
                    for (var i = 0; i < frames.length; i++) patch(frames[i]);
                  }
                  function start() {
                    scan(document);
                    var observer = new MutationObserver(function (mutations) {
                      for (var i = 0; i < mutations.length; i++) {
                        var nodes = mutations[i].addedNodes;
                        for (var j = 0; j < nodes.length; j++) {
                          var node = nodes[j];
                          if (!node || node.nodeType !== 1) continue;
                          if (node.tagName === 'IFRAME') patch(node);
                          else scan(node);
                        }
                      }
                    });
                    observer.observe(document.documentElement || document, { childList: true, subtree: true });
                  }
                  if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', start);
                  } else {
                    start();
                  }
                })();
              """,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          initialData: InAppWebViewInitialData(
            baseUrl: WebUri("https://widget.dojah.io"),
            historyUrl: WebUri("https://widget.dojah.io"),
            mimeType: "text/html",
            data: """
                      <html lang="en">
                        <head>
                            <meta charset="UTF-8">
                                <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1, maximum-scale=1, minimum-scale=1, shrink-to-fit=1"/>
                                <meta http-equiv="Permissions-Policy" content="camera=*, microphone=*, geolocation=*">
                              
                            <title>Dojah Inc.</title>
                        </head>
                        <body>
                  
   
                       <script src="https://widget.dojah.io/widget.js"></script>

                      
                        <script>
                                  window.__dojahLastMessage = null;
                                  window.addEventListener('message', function (event) {
                                    var origin = event.origin || '';
                                    if (origin !== 'https://identity.dojah.io' && origin !== 'https://widget.dojah.io') {
                                      return;
                                    }
                                    window.__dojahLastMessage = event.data || null;
                                  }, true);

                                  function dojahErrorPayload(error) {
                                    var message = window.__dojahLastMessage;
                                    var payload = error;
                                    // Current widget.js calls onError(data.response) for every
                                    // postMessage type. Unknown types arrive with a null response
                                    // and must not close the webview.
                                    if (payload == null && message && typeof message === 'object' && message.type && message.type !== 'connect.account.error') {
                                      return null;
                                    }
                                    if (payload == null && message && typeof message === 'object') {
                                      payload = message.response != null ? message.response : message;
                                    }
                                    if (payload == null) return null;
                                    if (typeof payload === 'object' && payload.type && payload.response == null && !payload.message && !payload.code && !payload.error) {
                                      return null;
                                    }
                                    try {
                                      return JSON.parse(JSON.stringify(payload));
                                    } catch (e) {
                                      return { message: String(payload) };
                                    }
                                  }

                                  const options = {
                                      app_id: "${widget.appId}",
                                      p_key: "${widget.publicKey}",
                                      type: "${widget.type}",
                                      reference_id: "${widget.referenceId}",
                                      config: ${json.encode(widget.config ?? {})},
                                      user_data: ${json.encode(widget.userData ?? {})},
                                      gov_data: ${json.encode(widget.govData ?? {})},
                                      gov_id: ${json.encode(widget.govId ?? {})},
                                      location: ${json.encode(locationObject ?? {})},
                                      metadata: ${json.encode(widget.metaData ?? {})},
                                      onSuccess: function (response) {
                                      window.flutter_inappwebview.callHandler('onSuccessCallback', response)
                                      },
                                      onError: function (error) {
                                        var payload = dojahErrorPayload(error);
                                        if (payload == null) return;
                                        window.flutter_inappwebview.callHandler('onErrorCallback', payload)
                                      },
                                      onClose: function () {
                                        window.flutter_inappwebview.callHandler('onCloseCallback', 'close')
                                      }
                                  }

                                    const connect = new Connect(options);
                                    connect.setup();
                                    connect.open();
                              </script>
                        </body>
                      </html>
                  """,
          ),
          initialUrlRequest: URLRequest(
            url: WebUri("https://widget.dojah.io"),
          ),
          pullToRefreshController: pullToRefreshController,
          onWebViewCreated: (controller) {
            _webViewController = controller;

            _webViewController.addJavaScriptHandler(
              handlerName: 'onSuccessCallback',
              callback: (response) {
                widget.success(response);
              },
            );

            _webViewController.addJavaScriptHandler(
              handlerName: 'onCloseCallback',
              callback: (response) {
                widget.close(response);
                // if (response.first == 'close') {
                //   Navigator.pop(context);
                // }
              },
            );

            _webViewController.addJavaScriptHandler(
              handlerName: 'onErrorCallback',
              callback: (error) {
                widget.error(error);
              },
            );
          },
          onPermissionRequest: (controller, permissionRequest) async {
            return PermissionResponse(
              resources: permissionRequest.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          onLoadStop: (controller, url) {
            pullToRefreshController.endRefreshing();
          },
          onReceivedError: (controller, url, code) {
            pullToRefreshController.endRefreshing();
          },
          onProgressChanged: (controller, progress) {
            if (progress == 100) {
              pullToRefreshController.endRefreshing();
            }
            setState(() {
              this.progress = progress / 100;
            });
          },
          androidOnPermissionRequest: (controller, origin, resources) async {
            return PermissionRequestResponse(
                resources: resources, action: PermissionRequestResponseAction.GRANT);
          },
          onGeolocationPermissionsShowPrompt: (controller, origin) async {
            return GeolocationPermissionShowPromptResponse(
              allow: true,
              origin: origin,
              retain: true,
            );
          },
          onConsoleMessage: (controller, consoleMessage) {},
        );
      },
    );

    if (widget.builder != null) {
      return widget.builder!(child);
    }

    return Scaffold(
      appBar: AppBar(),
      body: child,
    );
  }
}
