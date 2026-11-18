import 'package:flutter/cupertino.dart'
    show CupertinoAdaptiveTextSelectionToolbar, cupertinoTextSelectionHandleControls;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart'
    show BuildContext, EditableTextState, TextSelectionControls, Widget;
import 'package:fluent_ui/fluent_ui.dart' show TextBox;

/// Keep iOS-native selection handles, highlighting, and context toolbar.
/// Desktop selection remains Fluent-native.
TextSelectionControls? get waveTextSelectionControls =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? cupertinoTextSelectionHandleControls
        : null;

/// Use the iOS-native selection toolbar on iPhone and iPad. The Fluent
/// desktop toolbar includes keyboard-shortcut hints (Ctrl+C, Ctrl+V, etc.)
/// that are irrelevant on touch devices. Keep Fluent's menu on desktop.
Widget waveTextContextMenuBuilder(
  BuildContext context,
  EditableTextState state,
) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoAdaptiveTextSelectionToolbar.editableText(
      editableTextState: state,
    );
  }
  return TextBox.defaultContextMenuBuilder(context, state);
}
