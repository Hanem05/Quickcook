import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Checkbox row for terms acceptance with a tappable "Terms & Conditions" link.
class TermsAcceptanceRow extends StatelessWidget {
  const TermsAcceptanceRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.onViewTerms,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final VoidCallback? onViewTerms;

  static Future<void> showTermsDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms & Conditions'),
        content: SingleChildScrollView(
          child: Text(
            'By using QuickCook you agree to use the app responsibly, keep your '
            'account credentials private, and follow applicable laws. Recipe '
            'content is for personal use. We may update these terms; continued use '
            'means you accept the latest version.\n\n'
            'Contact support if you have questions about data use or account access.',
            style: TextStyle(
              color: cs.onSurface,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkStyle = TextStyle(
      color: cs.primary,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms & Conditions',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = onViewTerms ?? () => showTermsDialog(context),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
