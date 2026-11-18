import 'package:flutter/cupertino.dart'
    show cupertinoTextSelectionHandleControls;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart'
    show BuildContext, ContextMenuButtonItem, ContextMenuButtonType, EditableTextState, SizedBox, TextSelectionControls, Widget;
import 'package:fluent_ui/fluent_ui.dart'
    show TextBox, WindowsTextSelectionToolbar;

/// Keep iOS selection handles, but use the Fluent desktop-style toolbar.
/// Keyboard shortcut labels are suppressed by converting the menu items to
/// custom labeled actions before passing them to the Fluent toolbar.
TextSelectionControls? get waveTextSelectionControls =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? cupertinoTextSelectionHandleControls
        : null;

Widget waveTextContextMenuBuilder(
  BuildContext context,
  EditableTextState state,
) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final items = state.contextMenuButtonItems
        .map(
          (item) => ContextMenuButtonItem(
            type: ContextMenuButtonType.custom,
            label: item.label ?? _labelFor(item.type),
            onPressed: item.onPressed,
          ),
        )
        .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return WindowsTextSelectionToolbar(
      buttonItems: items,
      anchors: state.contextMenuAnchors,
    );
  }

  return TextBox.defaultContextMenuBuilder(context, state);
}

String _labelFor(ContextMenuButtonType type) => switch (type) {
  ContextMenuButtonType.cut => 'Cut',
  ContextMenuButtonType.copy => 'Copy',
  ContextMenuButtonType.paste => 'Paste',
  ContextMenuButtonType.selectAll => 'Select All',
  ContextMenuButtonType.delete => 'Delete',
  ContextMenuButtonType.lookUp => 'Look Up',
  ContextMenuButtonType.searchWeb => 'Search Web',
  ContextMenuButtonType.share => 'Share',
  ContextMenuButtonType.liveTextInput => 'Live Text Input',
  ContextMenuButtonType.custom => '',
};
