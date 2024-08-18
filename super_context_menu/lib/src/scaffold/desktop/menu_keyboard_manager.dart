
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum EnterMenuFrom {
  firstElement,
  lastElement,
}

class PopMenuResult {
  final bool pop;
  final bool allowPopLastMenu;
  PopMenuResult(this.pop, { this.allowPopLastMenu = false });
}

class MenuKeyboardManagerEvent {
  final BuildContext context;
  /// [KeyEvent]s besides [KeyDownEvent] are ignored.
  final KeyEvent keyEvent;

  const MenuKeyboardManagerEvent(this.context, this.keyEvent);
}

class MenuKeyboardResponse<T> {
  T result;
  /// If [true], the keyboard event will be consumed.
  /// By default, keyboard events are consumed. Specify [false]
  /// to prevent it.
  bool consume;

  MenuKeyboardResponse(this.result, { this.consume = true });
  KeyEventResult get desiredResult =>
    consume ? KeyEventResult.handled : KeyEventResult.ignored;
}

abstract class MenuKeyboardManager {
  /// Note: Returning [null] from the below functions indicates
  /// that the event will not happen, and the keyboard event
  /// will not be consumed.

  /// From a state where all menu items are unfocused (primary focus is on the)
  /// menu container, enter the menu from the top or bottom based on the key.
  /// Return null to avoid processing the action and prevent entering the menu.
  MenuKeyboardResponse<EnterMenuFrom>? enterMenuOnKey(
    MenuKeyboardManagerEvent event
  );
  /// If the current selected menu item is a [Menu] and 
  /// [true] is returned, the menu item is expanded into a submenu.
  MenuKeyboardResponse<bool>? expandMenuItemOnKey(MenuKeyboardManagerEvent event);
  /// Pops the currently active [Menu] if [true] is returned.
  MenuKeyboardResponse<PopMenuResult>? popMenuOnKey(MenuKeyboardManagerEvent event);
  /// Moves to the next menu item if [true] is returned.
  /// Note: This is called only when a menu item is focused. If the menu
  /// is focused, [enterMenuOnKey] is called.
  MenuKeyboardResponse<bool>? moveToNextMenuItemOnKey(MenuKeyboardManagerEvent event);
  /// Moves to the previous menu item if [true] is returned.
  /// Note: This is called only when a menu item is focused. If the menu
  /// is focused, [enterMenuOnKey] is called.
  MenuKeyboardResponse<bool>? moveToPrevMenuItemOnKey(MenuKeyboardManagerEvent event);
  /// Hides the entire context menu if [true] is returned.
  MenuKeyboardResponse<bool>? quitContextMenuOnKey(MenuKeyboardManagerEvent event);
  /// Activate the selected menu item if [true] is returned.
  MenuKeyboardResponse<bool>? activateMenuItemOnKey(MenuKeyboardManagerEvent event);
}

typedef _Key = LogicalKeyboardKey;
typedef _Response<T> = MenuKeyboardResponse<T>;

class DefaultMenuKeyboardManager implements MenuKeyboardManager {
  const DefaultMenuKeyboardManager();

  static LogicalKeyboardKey getHorizontalKey(BuildContext context, bool forward)
    => switch((forward, Directionality.of(context))) {
      (true, TextDirection.ltr) => _Key.arrowRight,
      (false, TextDirection.ltr) => _Key.arrowLeft,
      // RTL -> invert directional keys
      (_, TextDirection.rtl) => getHorizontalKey(context, !forward)
  };

  @override
  enterMenuOnKey(MenuKeyboardManagerEvent event)
    => switch(event.keyEvent.logicalKey) {
    _Key.arrowDown || _Key.arrowLeft || _Key.arrowRight
      => _Response(EnterMenuFrom.firstElement),
    _Key.arrowUp => _Response(EnterMenuFrom.lastElement),
    _ => null
  };
  
  @override
  expandMenuItemOnKey(MenuKeyboardManagerEvent event)
    => switch(event.keyEvent.logicalKey) {
    _Key.arrowRight => _Response(true),
    // Don't consume the keyboard event
    _ => null
  };
  
  @override
  moveToNextMenuItemOnKey(MenuKeyboardManagerEvent event)
    => switch(event.keyEvent.logicalKey) {
      _Key.arrowDown || _Key.enter => _Response(true),
      _ => null
    };
  
  @override
  moveToPrevMenuItemOnKey(MenuKeyboardManagerEvent event)
    => switch(event.keyEvent.logicalKey) {
      _Key.arrowUp => _Response(true),
      _ => null
  };
  
  @override
  popMenuOnKey(MenuKeyboardManagerEvent event) {
    final key = event.keyEvent.logicalKey;
    // Return 
    if (key == getHorizontalKey(event.context, false)) {
      return _Response(PopMenuResult(true));
    }
    return null;
  }
  
  @override
  quitContextMenuOnKey(MenuKeyboardManagerEvent event)
    => switch(event.keyEvent.logicalKey) {
      _Key.escape => _Response(true),
      _ => null
  };
  
  @override
  activateMenuItemOnKey(MenuKeyboardManagerEvent event)
    => switch(event.keyEvent.logicalKey) {
      _Key.enter => _Response(true, consume: false),
      _ => null
  };
  
}
