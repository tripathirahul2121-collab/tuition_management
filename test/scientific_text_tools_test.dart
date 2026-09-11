import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:tuition/core/text/scientific_text_tools.dart';

void main() {
  test(
    'converts chemistry formulas to subscript digits on explicit action',
    () {
      expect(convertFormulaDigitsToSubscript('Al2O3'), 'Al₂O₃');
      expect(convertFormulaDigitsToSubscript('H2SO4'), 'H₂SO₄');
      expect(convertFormulaDigitsToSubscript('Na2CO3'), 'Na₂CO₃');
      expect(convertFormulaDigitsToSubscript('Ca(OH)2'), 'Ca(OH)₂');
    },
  );

  test('applies subscript and superscript character maps', () {
    expect(applyScientificMode('234', ScientificScriptMode.subscript), '₂₃₄');
    expect(
      applyScientificMode('23+-', ScientificScriptMode.superscript),
      '²³⁺⁻',
    );
  });

  test('inserts text at current cursor position', () {
    final controller = TextEditingController(text: 'AlO');
    controller.selection = const TextSelection.collapsed(offset: 2);

    insertScientificText(controller, '2', mode: ScientificScriptMode.subscript);

    expect(controller.text, 'Al₂O');
    expect(controller.selection.baseOffset, 3);
  });

  test('formats newly typed characters in script mode', () {
    final formatter = ScientificScriptInputFormatter(
      ScientificScriptMode.subscript,
    );

    final next = formatter.formatEditUpdate(
      const TextEditingValue(
        text: 'Al',
        selection: TextSelection.collapsed(offset: 2),
      ),
      const TextEditingValue(
        text: 'Al2',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );

    expect(next.text, 'Al₂');
    expect(next.selection.baseOffset, 3);
  });
}
