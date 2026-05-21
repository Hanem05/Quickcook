import 'package:flutter/services.dart';

/// Matches Laravel `string` / MySQL `VARCHAR(255)` columns on `users`.
const int kDbVarchar255 = 255;

List<TextInputFormatter> varchar255AsciiFormatters() => [
  LengthLimitingTextInputFormatter(kDbVarchar255),
  FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]')),
];

String? validateVarchar255(String? value, {required String fieldLabel}) {
  if (value != null && value.length > kDbVarchar255) {
    return '$fieldLabel must be $kDbVarchar255 characters or fewer';
  }
  return null;
}

String? validatePassword255(String? value, {int minLength = 6}) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }
  if (value.length < minLength) {
    return 'Minimum $minLength characters';
  }
  return validateVarchar255(value, fieldLabel: 'Password');
}
