import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:super_context_menu/src/menu_internal.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:super_native_extensions/raw_menu.dart' as raw;

// ignore: implementation_imports
import 'package:super_native_extensions/src/mutex.dart';

import 'scaffold/desktop/menu_session.dart';
import 'util.dart';

class _ContextMenuDetector extends StatefulWidget {
  const _ContextMenuDetector({
    required this.hitTestBehavior,
    required this.contextMenuIsAllowed,
    required this.onShowContextMenu,
    required this.child,
  });

  final Widget child;
  final HitTestBehavior hitTestBehavior;
  final ContextMenuIsAllowed contextMenuIsAllowed;
  final OnShowContextMenu onShowContextMenu;

  @override
  State<StatefulWidget> createState() => _ContextMenuDetectorState();
}

class _ContextMenuDetectorState extends State<_ContextMenuDetector> {
  int? _pointerDown;
  Stopwatch? _pointerDownStopwatch;

  final _onPointerUp = SimpleNotifier();

  // Prevent nested detectors from showing context menu.
  static _ContextMenuDetectorState? _activeDetector;

  static final _mutex = Mutex();

  bool _acceptPrimaryButton() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return defaultTargetPlatform == TargetPlatform.macOS &&
        keys.length == 1 &&
        keys.contains(LogicalKeyboardKey.controlLeft);
  }

  bool _canAcceptEvent(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return false;
    }
    if (event.buttons == kSecondaryButton ||
        event.buttons == kPrimaryButton && _acceptPrimaryButton()) {
      return widget.contextMenuIsAllowed(event.position);
    }

    return false;
  }

  @override
  void dispose() {
    super.dispose();
    _mutex.protect(() async {
      if (_activeDetector == this) {
        _activeDetector = null;
      }
    });
  }

  void _showContextMenu(
    Offset position,
    Listenable onPointerUp,
    ValueChanged<bool> onMenuResolved,
    VoidCallback onClose,
  ) async {
    try {
      await widget.onShowContextMenu(position, onPointerUp, (value) {
        onMenuResolved(value);
      });
    } finally {
      onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.hitTestBehavior,
      onPointerDown: (event) {
        _mutex.protect(() async {
          if (_activeDetector != null) {
            return;
          }
          if (_canAcceptEvent(event)) {
            final menuResolvedCompleter = Completer<bool>();
            _showContextMenu(event.position, _onPointerUp, (value) {
              menuResolvedCompleter.complete(value);
            }, () {
              _mutex.protect(() async {
                if (_activeDetector == this) {
                  _activeDetector = null;
                }
              });
            });
            final menuResolved = await menuResolvedCompleter.future;
            if (menuResolved) {
              _activeDetector = this;
              _pointerDown = event.pointer;
              _pointerDownStopwatch = Stopwatch()..start();
            }
          }
        });
      },
      onPointerUp: (event) {
        if (_pointerDown == event.pointer) {
          _activeDetector = null;
          _pointerDown = null;
          // Pointer up would trigger currently selected item. Make sure we don't
          // do this on simple right click.
          if ((_pointerDownStopwatch?.elapsedMilliseconds ?? 0) > 300) {
            _onPointerUp.notify();
          }
          _pointerDownStopwatch = null;
        }
      },
      child: widget.child,
    );
  }
}

typedef DesktopDetectorWidgetBuilder = Widget Function({
  required BuildContext context,
  required HitTestBehavior hitTestBehavior,
  required ContextMenuIsAllowed contextMenuIsAllowed,
  required OnShowContextMenu onShowContextMenu,
  /// The actual context menu widget.
  required Widget child,
});

_ContextMenuDetector _defaultDesktopDetectorWidgetBuilder({
  required BuildContext context,
  required HitTestBehavior hitTestBehavior,
  required ContextMenuIsAllowed contextMenuIsAllowed,
  required OnShowContextMenu onShowContextMenu,
  /// The actual context menu widget.
  required Widget child
}) {
  return _ContextMenuDetector(
    hitTestBehavior: hitTestBehavior,
    contextMenuIsAllowed: contextMenuIsAllowed,
    onShowContextMenu: onShowContextMenu,
    child: child,
  );
}

class DesktopContextMenuWidget extends StatelessWidget {
  const DesktopContextMenuWidget({
    super.key,
    required this.child,
    required this.hitTestBehavior,
    required this.menuProvider,
    required this.contextMenuIsAllowed,
    required this.menuWidgetBuilder,
    DesktopDetectorWidgetBuilder? desktopDetectorWidgetBuilder,
    MenuKeyboardManager? menuKeyboardManager,
    this.menuOverlayBuilder,
    this.iconTheme,
  }): desktopDetectorWidgetBuilder =  
        desktopDetectorWidgetBuilder ?? _defaultDesktopDetectorWidgetBuilder,
      menuKeyboardManager =
        menuKeyboardManager ?? const DefaultMenuKeyboardManager();

  final HitTestBehavior hitTestBehavior;
  final MenuProvider menuProvider;
  final ContextMenuIsAllowed contextMenuIsAllowed;
  final DesktopMenuWidgetBuilder menuWidgetBuilder;
  final DesktopDetectorWidgetBuilder desktopDetectorWidgetBuilder;
  final MenuKeyboardManager menuKeyboardManager;
  final DesktopMenuOverlayBuilder? menuOverlayBuilder;

  final Widget child;

  /// Base icon theme for menu icons. The size will be overridden depending
  /// on platform.
  final IconThemeData? iconTheme;

  @override
  Widget build(BuildContext context) {
    return desktopDetectorWidgetBuilder(
      context: context,
      hitTestBehavior: hitTestBehavior,
      contextMenuIsAllowed: contextMenuIsAllowed,
      onShowContextMenu: (position, pointerUpListenable, onMenuresolved, { requestCloseNotifier }) async {
        await _onShowContextMenu(
          context,
          position,
          pointerUpListenable,
          onMenuresolved,
          requestCloseNotifier: requestCloseNotifier,
        );
      },
      // Used on web to determine whether to prevent browser context menu
      child: BaseContextMenuRenderWidget(
        contextMenuIsAllowed: contextMenuIsAllowed,
        getConfiguration: (_) async => null,
        hitTestBehavior: hitTestBehavior,
        child: child,
      ),
    );
  }

  raw.MenuSerializationOptions _serializationOptions(BuildContext context) {
    final mq = MediaQuery.of(context);
    final iconTheme = this.iconTheme ??
        const IconThemeData.fallback().copyWith(
          color: mq.platformBrightness == Brightness.light
              ? const Color(0xFF090909)
              : const Color(0xFFF0F0F0),
        );
    return raw.MenuSerializationOptions(
      iconTheme: iconTheme,
      destructiveIconTheme: iconTheme,
      devicePixelRatio: mq.devicePixelRatio,
    );
  }

  /// [onMenuResolved] Will be called with true if the provider resolved a valid menu that will be shown,
  ///                  false otherwise.
  Future<MenuResult?> _onShowContextMenu(
    BuildContext context,
    Offset globalPosition,
    Listenable? onInitialPointerUp,
    Function(bool) onMenuResolved,
    { Listenable? requestCloseNotifier, }
  ) async {
    MenuResult? menuResult;
    final onShowMenu = SimpleNotifier();
    final onHideMenu = ValueNotifier<raw.MenuResult?>(null);
    final onPreviewAction = SimpleNotifier();
    raw.MenuHandle? handle;
    try {
      final request = MenuRequest(
        onShowMenu: onShowMenu,
        onHideMenu: onHideMenu,
        onPreviewAction: onPreviewAction,
        location: globalPosition,
      );
      final menu = await menuProvider(request);
      final menuContext = await raw.MenuContext.instance();
      if (menu != null && context.mounted) {
        final serializationOptions = _serializationOptions(context);
        handle = await menuContext.registerMenu(
          menu,
          serializationOptions,
        );
        // ignore: use_build_context_synchronously
        if (!context.mounted) {
          onHideMenu.value = raw.MenuResult(itemSelected: false);
          onMenuResolved(false);
        }
        onMenuResolved(true);
        onShowMenu.notify();
        final request = raw.DesktopContextMenuRequest(
            iconTheme: serializationOptions.iconTheme,
            position: globalPosition,
            menu: handle,
            fallback: () {
              final completer = Completer<MenuResult>();
              ContextMenuSession(
                context: context,
                iconTheme: serializationOptions.iconTheme,
                menu: handle!.menu,
                menuWidgetBuilder: menuWidgetBuilder,
                menuKeyboardManager: menuKeyboardManager,
                onDone: (value) => completer.complete(value),
                onInitialPointerUp: onInitialPointerUp,
                requestCloseNotifier: requestCloseNotifier,
                menuOverlayBuilder: menuOverlayBuilder,
                position: globalPosition,
              );
              return completer.future;
            });
        final res = await menuContext.showContextMenu(request);
        onHideMenu.value = res;
        menuResult = res;
      } else {
        onMenuResolved(false);
      }
    } finally {
      onShowMenu.dispose();
      onPreviewAction.dispose();
      onHideMenu.dispose();
      handle?.dispose();
    }
    return menuResult;
  }
}
