import 'dart:async';
import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mutex/mutex.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

void main() async {
  runApp(const MainApp());
}

class Item extends StatelessWidget {
  const Item({
    super.key,
    this.color = Colors.blue,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final EdgeInsets padding;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: child,
      ),
    );
  }
}

class _PageLayout extends StatelessWidget {
  const _PageLayout({
    required this.itemZone,
    required this.dropZone,
  });

  final Widget itemZone;
  final Widget dropZone;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Flex(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          // textDirection: TextDirection.rtl,
          direction: constraints.maxWidth > constraints.maxHeight
              ? Axis.horizontal
              : Axis.vertical,
          children: [
            Expanded(
              flex: 5,
              child: itemZone,
            ),
            const SizedBox(width: 16, height: 16),
            Expanded(
              flex: 2,
              child: dropZone,
            ),
          ],
        ),
      );
    });
  }
}

class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.description,
    required this.child,
  });

  final Widget description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
          Padding(
            padding: const EdgeInsets.all(16.0).copyWith(top: 0),
            child: description,
          ),
        ],
      ),
    );
  }
}

class _BaseContextMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ContextMenuWidget(
      child: const Item(
        child: Text('Base Context Menu'),
      ),
      menuProvider: (_) {
        return Menu(
          children: [
            MenuAction(title: 'Menu Item 1', callback: () {}),
            MenuAction(title: 'Menu Item 2', callback: () {}),
            MenuAction(title: 'Menu Item 3', callback: () {}),
            MenuSeparator(),
            Menu(title: 'Submenu', children: [
              MenuAction(title: 'Submenu Item 1', callback: () {}),
              MenuAction(title: 'Submenu Item 2', callback: () {}),
              Menu(title: 'Nested Submenu', children: [
                MenuAction(title: 'Submenu Item 1', callback: () {}),
                MenuAction(title: 'Submenu Item 2', callback: () {}),
              ]),
            ]),
          ],
        );
      },
    );
  }
}

class _ContextMenuLClickDetector extends StatefulWidget {
  const _ContextMenuLClickDetector({
    required this.hitTestBehavior,
    required this.contextMenuIsAllowed,
    required this.onShowContextMenu,
    required this.child,
  });

  final Widget child;
  final HitTestBehavior hitTestBehavior;
  final ContextMenuIsAllowed contextMenuIsAllowed;
  final Future<void> Function(Offset, Listenable, Function(bool))
      onShowContextMenu;

  @override
  State<StatefulWidget> createState() => _ContextMenuLCickDetectorState();
}

class _ContextMenuLCickDetectorState extends State<_ContextMenuLClickDetector> {
  int? _pointerDown;
  Stopwatch? _pointerDownStopwatch;

  final _onPointerUp = ChangeNotifier();

  // Prevent nested detectors from showing context menu.
  static _ContextMenuLCickDetectorState? _activeDetector;

  static final _mutex = Mutex();

  bool _canAcceptEvent(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return false;
    }
    if (event.buttons == kPrimaryButton) {
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
            // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
            _onPointerUp.notifyListeners();
          }
          _pointerDownStopwatch = null;
        }
      },
      child: widget.child,
    );
  }
}

_ContextMenuLClickDetector _lClickDetector({
  required Widget child,
  required BuildContext context,
  required ContextMenuIsAllowed contextMenuIsAllowed,
  required HitTestBehavior hitTestBehavior,
  required OnShowContextMenu onShowContextMenu,
}) {
  return _ContextMenuLClickDetector(
    hitTestBehavior: hitTestBehavior,
    contextMenuIsAllowed: contextMenuIsAllowed,
    onShowContextMenu: onShowContextMenu,
    child: child
  );
}

class _BaseContextMenuWithLClickDetector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ContextMenuWidget(
      desktopDetectorWidgetBuilder: _lClickDetector,
      child: const Item(
        child: Text('Base Context Menu'),
      ),
      menuProvider: (_) {
        return Menu(
          children: [
            MenuAction(title: 'Menu Item 1', callback: () {}),
            MenuAction(title: 'Menu Item 2', callback: () {}),
            MenuAction(title: 'Menu Item 3', callback: () {}),
            MenuSeparator(),
            Menu(title: 'Submenu', children: [
              MenuAction(title: 'Submenu Item 1', callback: () {}),
              MenuAction(title: 'Submenu Item 2', callback: () {}),
              Menu(title: 'Nested Submenu', children: [
                MenuAction(title: 'Submenu Item 1', callback: () {}),
                MenuAction(title: 'Submenu Item 2', callback: () {}),
              ]),
            ]),
          ],
        );
      },
    );
  }
}

extension on SingleActivator {
  String stringRepresentation() {
    return [
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (meta) defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Meta',
      if (shift) 'Shift',
      trigger.keyLabel,
    ].join('+');
  }
}

extension on DesktopMenuInfo {
  bool get hasAnyCheckedItems => (resolvedChildren.any((element) =>
      element is MenuAction && element.state != MenuActionState.none));
}

class MenuAcceleratorBinding extends StatefulWidget {
  final Widget child;
  const MenuAcceleratorBinding({
    super.key,
    required this.child,
  });

  @override
  State<MenuAcceleratorBinding> createState() => MenuAcceleratorBindingState();
}

class MenuAcceleratorBindingState extends State<MenuAcceleratorBinding> {
  final subtreeFocusNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    subtreeFocusNode.dispose();
    super.dispose();
  }

  bool showAccelerators() => subtreeFocusNode.hasFocus;

  static MenuAcceleratorBindingState of(BuildContext context) {
    return maybeOf(context)!;
  }

  static MenuAcceleratorBindingState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<MenuAcceleratorBindingState>();
  }
  
  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: subtreeFocusNode,
      child: widget.child
    );
  }
}

class CustomMenuAcceleratorLabel extends StatefulWidget {
  final String label;
  final MenuAcceleratorChildBuilder labelBuilder;
  final VoidCallback onInvoke;

  const CustomMenuAcceleratorLabel({
    required this.label,
    required this.onInvoke,
    this.labelBuilder = MenuAcceleratorLabel.defaultLabelBuilder,
    super.key
  });

  @override
  State<CustomMenuAcceleratorLabel> createState() => _CustomMenuAcceleratorLabelState();
}


/// Whether [defaultTargetPlatform] is an Apple platform (Mac or iOS).
bool get _isApple {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return false;
  }
}


bool get _platformSupportsAccelerators {
  // On iOS and macOS, pressing the Option key (a.k.a. the Alt key) causes a
  // different set of characters to be generated, and the native menus don't
  // support accelerators anyhow, so we just disable accelerators on these
  // platforms.
  return !_isApple;
}

class _CustomMenuAcceleratorLabelState extends State<CustomMenuAcceleratorLabel> {
  late String _displayLabel;
  int _acceleratorIndex = -1;
  MenuAcceleratorBindingState? _binding;

  ShortcutRegistry? _shortcutRegistry;
  ShortcutRegistryEntry? _shortcutRegistryEntry;
  bool _showAccelerators = false;

  @override
  void initState() {
    super.initState();
    if (_platformSupportsAccelerators) {
      HardwareKeyboard.instance.addHandler(_listenToKeyEvent);
    }
    _updateDisplayLabel();
  }

  @override
  void dispose() {
    assert(_platformSupportsAccelerators || _shortcutRegistryEntry == null);
    _displayLabel = '';
    if (_platformSupportsAccelerators) {
      _shortcutRegistryEntry?.dispose();
      _shortcutRegistryEntry = null;
      _shortcutRegistry = null;
      HardwareKeyboard.instance.removeHandler(_listenToKeyEvent);
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_platformSupportsAccelerators) {
      return;
    }
    _shortcutRegistry = ShortcutRegistry.maybeOf(context);
    setState(() {
      _updateShowAccelerators();
      _updateAcceleratorShortcut();
    });
  }

  @override
  void didUpdateWidget(CustomMenuAcceleratorLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.label != oldWidget.label) {
      _updateDisplayLabel();
    }
  }

  void _updateShowAccelerators() {
    _showAccelerators = _binding?.showAccelerators() ?? false;
  }

  bool _listenToKeyEvent(KeyEvent event) {
    assert(_platformSupportsAccelerators);
    setState(() {
      _updateShowAccelerators();
      _updateAcceleratorShortcut();
    });
    // Just listening, so it doesn't ever handle a key.
    return false;
  }

  void _updateAcceleratorShortcut() {
    assert(_platformSupportsAccelerators);
    _shortcutRegistryEntry?.dispose();
    _shortcutRegistryEntry = null;
    // Before registering an accelerator as a shortcut it should meet these
    // conditions:
    //
    // 1) Is showing accelerators (i.e. Alt key is down).
    // 2) Has an accelerator marker in the label.
    // 3) Has an associated action callback for the label (from the
    //    MenuAcceleratorCallbackBinding).
    // 4) Is part of an anchor that either doesn't have a submenu, or doesn't
    //    have any submenus currently open (only the "deepest" open menu should
    //    have accelerator shortcuts registered).
    if (_showAccelerators && _acceleratorIndex != -1) {
      final String acceleratorCharacter = _displayLabel[_acceleratorIndex].toLowerCase();
      _shortcutRegistryEntry = _shortcutRegistry?.addAll(
        <ShortcutActivator, Intent>{
          CharacterActivator(acceleratorCharacter): VoidCallbackIntent(widget.onInvoke),
        },
      );
    }
  }

  void _updateDisplayLabel() {
    _displayLabel = MenuAcceleratorLabel.stripAcceleratorMarkers(
      widget.label,
      setIndex: (int index) {
        _acceleratorIndex = index;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _binding = MenuAcceleratorBindingState.maybeOf(context);
    _updateShowAccelerators();
    _updateAcceleratorShortcut();
    if (_binding == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
    }
    final int index = _showAccelerators ? _acceleratorIndex : -1;
    return widget.labelBuilder(context, _displayLabel, index);
  }
}

class CustomDesktopWidgetBuilder extends DefaultDesktopMenuWidgetBuilder {
  CustomDesktopWidgetBuilder({
    super.maxWidth
  });


  static DefaultDesktopMenuTheme _themeForContext(BuildContext context) {
    return DefaultDesktopMenuTheme.themeForBrightness(
        MediaQuery.platformBrightnessOf(context));
  }

  IconData? _stateToIcon(MenuActionState state) {
    switch (state) {
      case MenuActionState.none:
        return null;
      case MenuActionState.checkOn:
        return Icons.check;
      case MenuActionState.checkOff:
        return null;
      case MenuActionState.checkMixed:
        return Icons.remove;
      case MenuActionState.radioOn:
        return Icons.radio_button_on;
      case MenuActionState.radioOff:
        return Icons.radio_button_off;
    }
  }

  @override
  Widget buildMenuContainer(BuildContext context, DesktopMenuInfo menuInfo, Widget child) {
    /// Building a new menu container indicates that a new 'menu' instance is being created.
    /// In this case, we notify the currently active menu accelerator instance
    /// that it will gain a new submenu.
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final theme = _themeForContext(context);
    return Container(
      decoration: theme.decorationOuter.copyWith(
          borderRadius: BorderRadius.circular(6.0 + 1.0 / pixelRatio)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.all(1.0 / pixelRatio),
          child: Container(
            decoration: theme.decorationInner,
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14.0,
                decoration: TextDecoration.none,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: MenuAcceleratorBinding(
                  child: GroupIntrinsicWidthContainer(child: child)
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  Widget buildMenuItem(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    Key innerKey,
    DesktopMenuButtonState state,
    MenuElement element,
    VoidCallback onActivate
  ) {
    final itemInfo = DesktopMenuItemInfo(
      destructive: element is MenuAction && element.attributes.destructive,
      disabled: element is MenuAction && element.attributes.disabled,
      menuFocused: menuInfo.focused,
      selected: state.selected,
    );
    final theme = _themeForContext(context);
    final textStyle = theme.textStyleForItem(itemInfo);
    final iconTheme = menuInfo.iconTheme.copyWith(
      size: 16,
      color: textStyle.color,
    );
    final stateIcon =
        element is MenuAction ? _stateToIcon(element.state) : null;
    final Widget? prefix;
    if (stateIcon != null) {
      prefix = Icon(
        stateIcon,
        size: 16,
        color: iconTheme.color,
      );
    } else if (menuInfo.hasAnyCheckedItems) {
      prefix = const SizedBox(width: 16);
    } else {
      prefix = null;
    }
    final image = element.image?.asWidget(iconTheme);

    final Widget? suffix;
    if (element is Menu) {
      suffix = Icon(
        Icons.chevron_right_outlined,
        size: 18,
        color: iconTheme.color,
      );
    } else if (element is MenuAction) {
      final activator = element.activator?.stringRepresentation();
      if (activator != null) {
        suffix = Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: Text(
            activator,
            style: theme.textStyleForItemActivator(itemInfo, textStyle),
          ),
        );
      } else {
        suffix = null;
      }
    } else {
      suffix = null;
    }

    final child = element is DeferredMenuElement
        ? const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: Colors.grey,
              ),
            ),
          )
          : CustomMenuAcceleratorLabel(label: element.title ?? '', onInvoke: onActivate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: Container(
        key: innerKey,
        padding: const EdgeInsets.all(5),
        decoration: theme.decorationForItem(itemInfo),
        child: Row(
          children: [
            if (prefix != null) prefix,
            if (prefix != null) const SizedBox(width: 6.0),
            if (image != null) image,
            if (image != null) const SizedBox(width: 4.0),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: child,
              ),
            ),
            GroupIntrinsicWidth(
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (suffix != null) const SizedBox(width: 6.0),
                  if (suffix != null) suffix,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaseContextMenuWithAccelerators extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ContextMenuWidget(
      desktopMenuWidgetBuilder: CustomDesktopWidgetBuilder(),
      child: const Item(
        child: Text('Base Context Menu'),
      ),
      menuProvider: (_) {
        return Menu(
          children: [
            MenuAction(title: '&Open...', callback: () { print("open"); }),
            MenuAction(title: '&New...', callback: () { print("new");  }),
            MenuAction(title: '&Save...', callback: () { print("save"); }),
            MenuSeparator(),
            Menu(title: 'S&ubmenu', children: [
              MenuAction(title: 'Submenu Item 1', callback: () {}),
              MenuAction(title: '&Submenu Item 2', callback: () {}),
              Menu(title: 'N&ested Submenu', children: [
                MenuAction(title: 'Submenu Item 1', callback: () {}),
                MenuAction(title: 'Submenu Item 2', callback: () {}),
              ]),
            ]),
          ],
        );
      },
    );
  }
}

class _BaseContextMenuWithDrag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      dragItemProvider: (_) => DragItem(localData: 'LocalDragData'),
      child: DraggableWidget(
        child: ContextMenuWidget(
          child: const Item(
            child: Text('Base Context Menu with Drag'),
          ),
          menuProvider: (_) {
            return Menu(
              children: [
                MenuAction(title: 'Menu Item 1', callback: () {}),
                MenuAction(title: 'Menu Item 2', callback: () {}),
                MenuAction(title: 'Menu Item 3', callback: () {}),
                MenuSeparator(),
                Menu(title: 'Submenu', children: [
                  MenuAction(title: 'Submenu Item 1', callback: () {}),
                  MenuAction(title: 'Submenu Item 2', callback: () {}),
                  Menu(title: 'Submenu', children: [
                    MenuAction(title: 'Submenu Item 1', callback: () {}),
                    MenuAction(title: 'Submenu Item 2', callback: () {}),
                  ]),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeferredMenuPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      dragItemProvider: (_) => DragItem(localData: 'LocalDragData'),
      child: DraggableWidget(
        child: ContextMenuWidget(
          child: const Item(
            child: Text('Deferred context menu preview'),
          ),
          deferredPreviewBuilder: (context, child, cancellationToken) {
            return DeferredMenuPreview(
              const Size(200, 150),
              Future.delayed(
                const Duration(seconds: 2),
                () {
                  return const Item(
                    color: Colors.blue,
                    child: Text('Deferred menu preview'),
                  );
                },
              ),
            );
          },
          menuProvider: (_) {
            return Menu(
              children: [
                MenuAction(title: 'Menu Item 1', callback: () {}),
                MenuAction(title: 'Menu Item 2', callback: () {}),
                MenuAction(title: 'Menu Item 3', callback: () {}),
                MenuSeparator(),
                Menu(title: 'Submenu', children: [
                  MenuAction(title: 'Submenu Item 1', callback: () {}),
                  MenuAction(title: 'Submenu Item 2', callback: () {}),
                  Menu(title: 'Submenu', children: [
                    MenuAction(title: 'Submenu Item 1', callback: () {}),
                    MenuAction(title: 'Submenu Item 2', callback: () {}),
                  ]),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DropZone extends StatefulWidget {
  const _DropZone();

  @override
  State<StatefulWidget> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _inside = false;

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [], // local data only
      onDropOver: (event) {
        return DropOperation.copy;
      },
      onDropEnter: (_) {
        setState(() {
          _inside = true;
        });
      },
      onDropLeave: (_) {
        setState(() {
          _inside = false;
        });
      },
      onPerformDrop: (event) async {},
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(width: 1, color: Colors.blueGrey.shade300),
          color: _inside ? Colors.blue.shade200 : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: const Text('Drop Zone'),
      ),
    );
  }
}

class _ComplexContextMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      dragItemProvider: (_) => DragItem(localData: 'LocalDragData'),
      dragBuilder: (context, child) => const Item(
        color: Colors.teal,
        child: Text('Custom Drag preview'),
      ),
      child: DraggableWidget(
        child: ContextMenuWidget(
          liftBuilder: (context, child) {
            return Item(
              color: Colors.red,
              child: (child as Item).child,
            );
          },
          previewBuilder: (context, child) {
            return Item(
              color: Colors.amber.shade600,
              padding: const EdgeInsets.all(24),
              child: const Text('Custom menu preview'),
            );
          },
          child: const Item(
            child: Text('Complex Context Menu'),
          ),
          menuProvider: (_) {
            return Menu(
              children: [
                MenuAction(
                  image: MenuImage.icon(Icons.access_time),
                  title: 'Menu Item 1',
                  callback: () {},
                ),
                MenuAction(
                  title: 'Disabled Menu Item',
                  image: MenuImage.icon(Icons.replay_outlined),
                  attributes: const MenuActionAttributes(disabled: true),
                  callback: () {},
                ),
                MenuAction(
                  title: 'Destructive Menu Item',
                  image: MenuImage.icon(Icons.delete),
                  attributes: const MenuActionAttributes(destructive: true),
                  callback: () {},
                ),
                MenuSeparator(),
                Menu(title: 'Submenu', children: [
                  MenuAction(title: 'Submenu Item 1', callback: () {}),
                  MenuAction(title: 'Submenu Item 2', callback: () {}),
                ]),
                Menu(title: 'Deferred Item Example', children: [
                  MenuAction(title: 'Leading Item', callback: () {}),
                  DeferredMenuElement((_) async {
                    await Future.delayed(const Duration(seconds: 2));
                    return [
                      MenuSeparator(),
                      MenuAction(title: 'Lazily Loaded Item', callback: () {}),
                      Menu(title: 'Lazily Loaded Submenu', children: [
                        MenuAction(title: 'Submenu Item 1', callback: () {}),
                        MenuAction(title: 'Submenu Item 2', callback: () {}),
                      ]),
                      MenuSeparator(),
                    ];
                  }),
                  MenuAction(title: 'Trailing Item', callback: () {}),
                ]),
                MenuSeparator(),
                MenuAction(
                  title: 'Checked Menu Item',
                  state: MenuActionState.checkOn,
                  callback: () {},
                ),
                MenuAction(
                  title: 'Menu Item in Mixed State',
                  state: MenuActionState.checkMixed,
                  callback: () {},
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 16);
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: _PageLayout(
            itemZone: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Section(
                    description:
                        const Text('Base context menu, without drag & drop.'),
                    child: _BaseContextMenu(),
                  ),
                  Section(
                    description:
                      const Text('Base context menu with left-click detection.'),
                    child: _BaseContextMenuWithLClickDetector()
                  ),
                  Section(
                    description:
                      const Text('Base context menu, with keyboard accelerators (desktop only).'),
                    child: _BaseContextMenuWithAccelerators(),
                  ),
                  Section(
                    description:
                        const Text('Base context menu, with drag & drop.'),
                    child: _BaseContextMenuWithDrag(),
                  ),
                  Section(
                    description: const Text(
                        'Complex context menu, with custom lift, preview and drag builders (mobile only).'),
                    child: _ComplexContextMenu(),
                  ),
                  Section(
                    description:
                        const Text('Deferred menu preview (mobile only).'),
                    child: _DeferredMenuPreview(),
                  ),
                ].intersperse(const _Separator()).toList(growable: false),
              ),
            ),
            dropZone: const _DropZone(),
          ),
        ),
      ),
    );
  }
}

extension IntersperseExtensions<T> on Iterable<T> {
  Iterable<T> intersperse(T element) sync* {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      yield iterator.current;
      while (iterator.moveNext()) {
        yield element;
        yield iterator.current;
      }
    }
  }
}
