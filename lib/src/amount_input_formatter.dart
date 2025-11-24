import 'package:amount_input_formatter/src/number_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Number Formatter that is intended to be used together with the [TextField]
/// widget.
/// It is a minimalistic and configurable approach to number formatting that
/// uses no additional dependencies other than Dart and Flutter.
class AmountInputFormatter extends TextInputFormatter {
  /// The default configurable constructor.
  /// [integralLength] - sets the limit to length of integral part of
  /// the number. For example here: 11111.222 it will be the 11111
  /// part before the dot.
  /// [groupSeparator] - sets the "thousands" separator symbol that
  /// should separate an integral part of the number into chunks after a
  /// certain number of characters.
  /// [decimalSeparator] - sets the separator symbol that seats between the
  /// integral and decimal parts of the number. Typically it's a '.' or an ','
  /// depending on the language.
  /// [groupedDigits] - The number of digits that should be grouped in
  /// an integral part of the number before separation. Setting it, for example,
  /// to 3 for the number 12345.123 will result in the following formatting:
  /// 12,345.123.
  /// [fractionalDigits] - will limit the number of digits after the decimal
  /// separator.
  /// [initialValue] - the initial numerical value that is supplied to the
  /// formatter. Be aware that setting this value won't change the text
  /// displayed in [TextField] or the value in [TextEditingController].
  factory AmountInputFormatter({
    int integralLength = NumberFormatter.kIntegralLengthLimit,
    String groupSeparator = NumberFormatter.kComma,
    String decimalSeparator = NumberFormatter.kDot,
    int groupedDigits = 3,
    int fractionalDigits = 3,
    bool isEmptyAllowed = false,
    num? initialValue,
  }) {
    return AmountInputFormatter.withFormatter(
      formatter: NumberFormatter(
        initialValue: initialValue,
        integralLength: integralLength,
        groupSeparator: groupSeparator,
        groupedDigits: groupedDigits,
        decimalSeparator: decimalSeparator,
        fractionalDigits: fractionalDigits,
        isEmptyAllowed: isEmptyAllowed,
      ),
    );
  }

  /// Constructor that allows setting the underlying [NumberFormatter] instance.
  const AmountInputFormatter.withFormatter({
    required this.formatter,
  });

  /// Underlying [NumberFormatter] instance.
  final NumberFormatter formatter;

  /// Getter for the underlying decimal number, returns 0 in case of
  /// empty String value.
  double get doubleValue => formatter.doubleValue;

  /// Getter for the formatted String representation of the number.
  /// This value is the one that is displayed in the [TextField] and is
  /// returned from [TextEditingController.text] getter.
  String get formattedValue => formatter.formattedValue;

  /// Getter that wraps the formatted string of the number with Unicode
  /// "Left-To-Right Embedding" (LRE) and "Pop Directional Formatting" (PDF)
  /// characters to force the formatted-string-number to be correctly displayed
  /// left-to-right inside of the otherwise RTL context
  String get ltrEnforcedValue => formatter.ltrEnforcedValue;

  /// A boolean flag that controls if clearing the whole formatted value
  /// is allowed.
  /// If false clearing the whole [TextField] will set the text
  /// value to "0.[ftlDigits * 0]"
  bool get isEmptyAllowed => formatter.isEmptyAllowed;

  int _calculateSelectionOffset({
    required TextEditingValue oldValue,
    required TextEditingValue newValue,
    required String newText,
  }) {
    // Special case: Handle when user types "-" on zero value
    // The formatted value will be "-0" (or "-0.000"), cursor should be after "-0"
    final oldTextStartsWithMinus = oldValue.text.startsWith('-');
    final newTextStartsWithMinus = newText.startsWith('-');
    if (formatter.doubleValue == 0 &&
        newTextStartsWithMinus &&
        !oldTextStartsWithMinus &&
        (oldValue.text == '0' ||
            oldValue.text.isEmpty ||
            oldValue.text.replaceAll(RegExp('[^0-9.]'), '').replaceAll('.', '') == '0')) {
      // User typed "-" on zero, position cursor after "-0" (at indexOfDot)
      return formatter.indexOfDot;
    }

    // Special case: Handle when user types a digit after "-0"
    // Transition from "-0" to negative number (e.g., "-1")
    // Check if we're transitioning from zero to a small negative number
    final isTypingDigitAfterNegativeZero = formatter.previousValue == 0 &&
        formatter.doubleValue < 0 &&
        oldTextStartsWithMinus &&
        newTextStartsWithMinus &&
        formatter.doubleValue.abs() <= 9;

    if (isTypingDigitAfterNegativeZero) {
      // User typed a digit after "-0", position cursor after the digit (at indexOfDot)
      // This prevents cursor from jumping to decimal separator
      return formatter.indexOfDot;
    }

    // Assuming that it is the start of the input set the selection to the end
    // of the integer part.
    if (oldValue.selection.baseOffset <= 1 && formatter.doubleValue.abs() <= 9) {
      if (newText.isEmpty) return 0;

      if (formatter.doubleValue == 0) {
        if (formatter.previousValue == 0 &&
            formatter.ftlDigits > 0 &&
            (newValue.selection.baseOffset > 1 || oldValue.text.isEmpty)) {
          return formatter.indexOfDot + 1;
        }

        return formatter.indexOfDot;
      }
    }

    // Assuming that it is the start of the input set the selection to the
    // end of the integer part.
    // Handle small numbers (including negative) when cursor is at start
    if (oldValue.selection.baseOffset <= 1 &&
        formatter.doubleValue.abs() <= 9 &&
        formatter.previousValue.abs() <= 9) {
      return formatter.indexOfDot;
    }

    // Case if the overall text length didn't change
    // (i.e. one character replacement).
    if (oldValue.text.length == newText.length) {
      // Special case: If we're typing a digit after "-0", use indexOfDot instead of newSelection
      if (isTypingDigitAfterNegativeZero) {
        return formatter.indexOfDot;
      }

      final oldSelection = oldValue.selection;
      final newSelection = newValue.selection;

      if (newSelection.baseOffset > oldSelection.baseOffset) {
        return newSelection.baseOffset > newText.length ? newText.length : newSelection.baseOffset;
      }

      return newSelection.baseOffset;
    }

    // Calculating the offset if the previous conditions were folded.
    var offset = 0;

    if (newText.length < oldValue.text.length) {
      offset = oldValue.text.length - newText.length > 1
          ? oldValue.selection.baseOffset - (oldValue.text.length - newText.length)
          : oldValue.selection.baseOffset - 1;
      return offset < 0 ? 0 : offset;
    }

    offset = newText.length - oldValue.text.length > 1
        ? oldValue.selection.baseOffset + (newText.length - oldValue.text.length)
        : oldValue.selection.baseOffset + 1;

    return offset > newText.length ? newText.length - 1 : offset;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = formatter.processTextValue(
      textInput: newValue.text,
    );

    // If newText variable at this point equals to null that means that
    // formatting failed or was rejected.
    // Fall back to old value in this case.
    if (newText == null) return oldValue;

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(
        offset: _calculateSelectionOffset(
          oldValue: oldValue,
          newValue: newValue,
          newText: newText,
        ),
      ),
    );
  }

  /// Processes and formats the given numerical value through the
  /// formatter.
  /// Returns the formatted string representation of the number.
  ///
  /// Be aware that calling this method won't change the value of the
  /// [TextField] to which this formatter is attached to.
  /// Pass the [TextEditingController] used with this formatter to the
  /// [attachedController] argument to sync the [TextField] value with
  /// the formatter.
  String setNumber(
    num number, {
    TextEditingController? attachedController,
  }) {
    final formattedText = formatter.setNumValue(number);
    if (attachedController == null) return formattedText;

    attachedController.value = TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formatter.indexOfDot),
    );

    return attachedController.text;
  }

  /// Clears underlying Formatter data by:
  /// Setting the formatted value to empty sting;
  /// Setting the double value to 0;
  /// Setting the index of the decimal floating point to -1.
  /// Formatter settings will remain unchanged.
  String clear() => formatter.clear();
}
