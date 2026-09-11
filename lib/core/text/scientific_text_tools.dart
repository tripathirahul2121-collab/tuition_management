import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ScientificScriptMode { normal, subscript, superscript }

const subscriptCharacters = {
  '0': '₀',
  '1': '₁',
  '2': '₂',
  '3': '₃',
  '4': '₄',
  '5': '₅',
  '6': '₆',
  '7': '₇',
  '8': '₈',
  '9': '₉',
};

const superscriptCharacters = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
  '+': '⁺',
  '-': '⁻',
};

String applyScientificMode(String input, ScientificScriptMode mode) {
  final map = switch (mode) {
    ScientificScriptMode.subscript => subscriptCharacters,
    ScientificScriptMode.superscript => superscriptCharacters,
    ScientificScriptMode.normal => const <String, String>{},
  };
  if (map.isEmpty) return input;
  return input.split('').map((char) => map[char] ?? char).join();
}

String convertFormulaDigitsToSubscript(String input) {
  final buffer = StringBuffer();
  var previousWasLetterOrClose = false;

  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final subscript = subscriptCharacters[char];
    if (subscript != null && previousWasLetterOrClose) {
      buffer.write(subscript);
    } else {
      buffer.write(char);
    }
    previousWasLetterOrClose =
        RegExp(r'[A-Za-z\)]').hasMatch(char) ||
        subscript != null ||
        subscriptCharacters.containsValue(char);
  }

  return buffer.toString();
}

void insertScientificText(
  TextEditingController controller,
  String value, {
  ScientificScriptMode mode = ScientificScriptMode.normal,
}) {
  final text = controller.text;
  final selection = controller.selection;
  final start = selection.isValid ? selection.start : text.length;
  final end = selection.isValid ? selection.end : text.length;
  final insertValue = applyScientificMode(value, mode);
  final nextText = text.replaceRange(start, end, insertValue);
  final cursor = start + insertValue.length;

  controller.value = TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: cursor),
  );
}

void convertSelectedScientificText(
  TextEditingController controller,
  ScientificScriptMode mode,
) {
  final selection = controller.selection;
  if (!selection.isValid || selection.isCollapsed) return;
  final text = controller.text;
  final start = selection.start;
  final end = selection.end;
  final replacement = applyScientificMode(text.substring(start, end), mode);
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, replacement),
    selection: TextSelection(
      baseOffset: start,
      extentOffset: start + replacement.length,
    ),
  );
}

class ScientificScriptInputFormatter extends TextInputFormatter {
  ScientificScriptInputFormatter(this.mode);

  final ScientificScriptMode mode;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (mode == ScientificScriptMode.normal || oldValue.text == newValue.text) {
      return newValue;
    }

    var prefixLength = 0;
    final minLength = oldValue.text.length < newValue.text.length
        ? oldValue.text.length
        : newValue.text.length;
    while (prefixLength < minLength &&
        oldValue.text.codeUnitAt(prefixLength) ==
            newValue.text.codeUnitAt(prefixLength)) {
      prefixLength++;
    }

    var oldSuffix = oldValue.text.length;
    var newSuffix = newValue.text.length;
    while (oldSuffix > prefixLength &&
        newSuffix > prefixLength &&
        oldValue.text.codeUnitAt(oldSuffix - 1) ==
            newValue.text.codeUnitAt(newSuffix - 1)) {
      oldSuffix--;
      newSuffix--;
    }

    final changed = newValue.text.substring(prefixLength, newSuffix);
    final converted = applyScientificMode(changed, mode);
    final nextText =
        newValue.text.substring(0, prefixLength) +
        converted +
        newValue.text.substring(newSuffix);
    final delta = converted.length - changed.length;

    return newValue.copyWith(
      text: nextText,
      selection: newValue.selection.copyWith(
        baseOffset: (newValue.selection.baseOffset + delta).clamp(
          0,
          nextText.length,
        ),
        extentOffset: (newValue.selection.extentOffset + delta).clamp(
          0,
          nextText.length,
        ),
      ),
      composing: TextRange.empty,
    );
  }
}
