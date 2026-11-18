import 'package:flutter/cupertino.dart' show cupertinoTextSelectionControls;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart'
    show BuildContext, EditableTextState, TextSelectionControls, Widget;
import 'package:fluent_ui/fluent_ui.dart' show TextBox;

/// Use Flutter's built-in iOS controls, including its Cupertino selection
/// toolbar. The handle-only Cupertino variant depends on a custom context
/// menu builder and was leaving an empty Fluent/grey toolbar on iOS.
TextSelectionControls? get waveTextSelectionControls =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? cupertinoTextSelectionControls
        : null;

/// Keep Fluent's keyboard-shortcut context menu on desktop. On iOS this
/// builder is bypassed intentionally: [cupertinoTextSelectionControls]
/// provides the built-in Cupertino copy/cut/paste/select-all toolbar.
Widget waveTextContextMenuBuilder(
  BuildContext context,
  EditableTextState state,
) {
  return TextBox.defaultContextMenuBuilder(context, state);
}
