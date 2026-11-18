import 'package:flutter/cupertino.dart'
    show
        CupertinoTextSelectionToolbar,
        CupertinoTextSelectionToolbarButton,
        cupertinoTextSelectionHandleControls;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart'
    show BuildContext, EditableTextState, SizedBox, TextSelectionControls, Widget;
import 'package:fluent_ui/fluent_ui.dart' show TextBox;

/// Keep the iOS selection handles while delegating its toolbar to the
/// modern contextMenuBuilder below. Do not use cupertinoTextSelectionControls:
/// its legacy buildToolbar path is incompatible with Fluent TextBox overlays.
TextSelectionControls? get waveTextSelectionControls =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? cupertinoTextSelectionHandleControls
        : null;

/// Build a compact, native Cupertino selection toolbar on iOS. Avoid
/// Fluent's Windows/Acrylic menu there; it produces a translucent overlay
/// across the editable region instead of the expected iOS action bubble.
Widget waveTextContextMenuBuilder(
  BuildContext context,
  EditableTextState state,
) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final items = state.contextMenuButtonItems;
    if (items.isEmpty) return const SizedBox.shrink();

    return CupertinoTextSelectionToolbar(
      anchorAbove: state.contextMenuAnchors.primaryAnchor,
      anchorBelow:
          state.contextMenuAnchors.secondaryAnchor ??
          state.contextMenuAnchors.primaryAnchor,
      children: [
        for (final item in items)
          CupertinoTextSelectionToolbarButton.buttonItem(buttonItem: item),
      ],
    );
  }

  return TextBox.defaultContextMenuBuilder(context, state);
}
