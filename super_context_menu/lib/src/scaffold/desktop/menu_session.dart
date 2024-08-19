import 'package:flutter/widgets.dart';
import 'package:super_context_menu/src/scaffold/desktop/menu_widget_builder.dart';

import '../../menu_model.dart';
import 'menu_container.dart';
import 'menu_keyboard_manager.dart';

Widget _defaultOverlayBuilder(BuildContext context, Widget child) => child;

class ContextMenuSession implements MenuContainerDelegate {
  ContextMenuSession({
    required BuildContext context,
    required DesktopMenuWidgetBuilder menuWidgetBuilder,
    required MenuKeyboardManager menuKeyboardManager,
    required Menu menu,
    required Offset position,
    required IconThemeData iconTheme,
    Listenable? onInitialPointerUp,
    Listenable? requestCloseNotifier,
    DesktopMenuOverlayBuilder? menuOverlayBuilder,
    required this.onDone,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBuilder = menuOverlayBuilder ?? _defaultOverlayBuilder;
    _entry = OverlayEntry(
      builder: (context) => overlayBuilder.call(context, MenuContainer(
          rootMenu: menu,
          rootMenuPosition: position,
          delegate: this,
          menuWidgetBuilder: menuWidgetBuilder,
          iconTheme: iconTheme,
          onInitialPointerUp: onInitialPointerUp,
          requestCloseNotifier: requestCloseNotifier,
          keyboardManager: menuKeyboardManager,
        )
      ),
      opaque: false,
    );
    overlay.insert(_entry);
  }

  final ValueSetter<MenuResult> onDone;
  late OverlayEntry _entry;

  @override
  void hide({
    required bool itemSelected,
  }) {
    onDone(MenuResult(itemSelected: itemSelected));
    _entry.remove();
  }
}
