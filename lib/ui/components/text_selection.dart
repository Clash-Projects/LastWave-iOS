import 'package:flutter/cupertino.dart' show cupertinoTextSelectionHandleControls;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart'
    show BuildContext, EditableTextState, SizedBox, TextSelectionControls, Widget;
import 'package:fluent_ui/fluent_ui.dart' show TextBox;

/// Keep iOS-native selection handles and text highlighting, but hide the
/// floating context toolbar. Desktop selection remains Fluent-native.
TextSelectionControls? get waveTextSelectionControls =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? cupertinoTextSelectionHandleControls
        : null;

/// Keep the platform selection toolbar available on iOS. Hiding this
/// builder removes Paste and Copy from TextBox fields, including secure
/// credential fields such as the Last.fm shared secret.
Widget waveTextContextMenuBuilder(
  BuildContext context,
  EditableTextState state,
) =>
    TextBox.defaultContextMenuBuilder(context, state);
