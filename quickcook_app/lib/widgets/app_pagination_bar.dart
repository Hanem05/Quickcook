import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Numbered pagination: First « 1 2 3 » Last (active page in a circle).
class AppPaginationBar extends StatelessWidget {
  const AppPaginationBar({
    super.key,
    this.summary,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.accentColor = AppColors.brandLight,
    this.maxVisiblePages = 5,
    this.showFullPageList = true,
    this.showLast = true,
    this.textColor,
  });

  final String? summary;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final Color accentColor;
  final int maxVisiblePages;
  final bool showFullPageList;
  final bool showLast;
  final Color? textColor;

  List<int> _pageWindow(int total) {
    final current = currentPage.clamp(1, total);
    if (total <= maxVisiblePages) {
      return List.generate(total, (i) => i + 1);
    }
    var start = current - maxVisiblePages ~/ 2;
    if (start < 1) start = 1;
    var end = start + maxVisiblePages - 1;
    if (end > total) {
      end = total;
      start = (end - maxVisiblePages + 1).clamp(1, total);
    }
    return List.generate(end - start + 1, (i) => start + i);
  }

  @override
  Widget build(BuildContext context) {
    final total = totalPages < 1 ? 1 : totalPages;
    final current = currentPage.clamp(1, total);
    final inactive = textColor ?? Colors.grey.shade500;

    Widget textControl(
      String label, {
      VoidCallback? onTap,
      bool active = false,
    }) {
      if (active) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        );
      }

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null ? inactive.withValues(alpha: 0.45) : inactive,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    final controls = <Widget>[
      textControl(
        'First',
        onTap: current > 1 ? () => onPageChanged(1) : null,
      ),
      const SizedBox(width: 6),
      textControl(
        '«',
        onTap: current > 1 ? () => onPageChanged(current - 1) : null,
      ),
      const SizedBox(width: 8),
      if (showFullPageList && total > 1)
        ..._pageWindow(total).expand((p) sync* {
          yield Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: textControl(
              '$p',
              onTap: p == current ? null : () => onPageChanged(p),
              active: p == current,
            ),
          );
        })
      else
        textControl('$current', active: true),
      const SizedBox(width: 8),
      textControl(
        '»',
        onTap: current < total ? () => onPageChanged(current + 1) : null,
      ),
      const SizedBox(width: 6),
      if (showLast)
        textControl(
          'Last',
          onTap: current < total ? () => onPageChanged(total) : null,
        ),
    ];

    return Row(
      children: [
        if (summary != null && summary!.isNotEmpty)
          Expanded(
            child: Text(
              summary!,
              style: TextStyle(
                color: inactive,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          )
        else
          const Spacer(),
        Row(mainAxisSize: MainAxisSize.min, children: controls),
      ],
    );
  }
}
