import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/printer/label_builder.dart';
import '../../../services/printer/label_document.dart';

/// Render dokumen tag ke layar - meniru hasil kertas 58mm.
///
/// Sumbernya sama persis dengan yang dikirim ke printer ([LabelDocument]),
/// jadi preview ini bukan tiruan manual melainkan hasil render dokumen cetak.
class LabelPaper extends StatelessWidget {
  const LabelPaper({
    super.key,
    required this.document,
    this.watermark,
    this.watermarkColor = AppColors.danger,
  });

  final LabelDocument document;

  /// Teks besar melintang di atas kertas (mis. "SUDAH DICETAK", "DIBATALKAN").
  final String? watermark;
  final Color watermarkColor;

  static const double _paperWidth = 300;

  @override
  Widget build(BuildContext context) {
    final paper = Container(
      width: _paperWidth,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: document.elements.map(_buildElement).toList(),
      ),
    );

    if (watermark == null) return paper;

    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.55, child: paper),
        Transform.rotate(
          angle: -0.35,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: watermarkColor, width: 3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              watermark!,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: watermarkColor,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildElement(LabelElement element) {
    switch (element) {
      case LabelText():
        final text = Text(
          element.text,
          textAlign: _textAlign(element.align),
          style: _textStyle(element.size, element.bold),
        );
        final isHeadline = element.size == LabelTextSize.large ||
            element.size == LabelTextSize.xlarge;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          // Nomor tag selalu satu baris - dikecilkan otomatis bila kepanjangan.
          child: isHeadline
              ? FittedBox(fit: BoxFit.scaleDown, child: text)
              : text,
        );
      case LabelKeyValue():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 74,
                child: Text(
                  element.continuation ? '' : element.key,
                  style: _monospace(11.5, FontWeight.w500)
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
              Text(
                element.continuation ? '  ' : ': ',
                style: _monospace(11.5, FontWeight.w500),
              ),
              Expanded(
                child: Text(
                  element.value,
                  style: _monospace(
                    11.5,
                    element.bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      case LabelDivider():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: ClipRect(
            child: Text(
              LabelBuilder.renderDivider(element, document.charPerLine * 2),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: _monospace(11, FontWeight.w400)
                  .copyWith(color: AppColors.textMuted, height: 1),
            ),
          ),
        );
      case LabelQr():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: QrImageView(
              data: element.data,
              size: 118,
              version: QrVersions.auto,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
            ),
          ),
        );
      case LabelBoxGrid():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _boxGrid(element),
        );
      case LabelFeed():
        return SizedBox(height: 6.0 * element.lines);
    }
  }

  /// Di printer kotak ini digambar memakai karakter ASCII; di layar digambar
  /// sebagai kotak sungguhan supaya proporsinya sama dengan hasil cetak.
  Widget _boxGrid(LabelBoxGrid element) {
    final rows = <Widget>[];
    for (var start = 0; start < element.titles.length; start += element.columns) {
      final cells = <Widget>[];
      for (var col = 0; col < element.columns; col++) {
        final index = start + col;
        cells.add(
          Expanded(
            child: Container(
              height: 14.0 * element.rowHeight + 16,
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 0.9),
              ),
              child: Text(
                index < element.titles.length ? element.titles[index] : '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _monospace(10.5, FontWeight.w600),
              ),
            ),
          ),
        );
      }
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells));
    }
    return Column(children: rows);
  }

  TextAlign _textAlign(LabelAlign align) {
    switch (align) {
      case LabelAlign.left:
        return TextAlign.left;
      case LabelAlign.center:
        return TextAlign.center;
      case LabelAlign.right:
        return TextAlign.right;
    }
  }

  TextStyle _textStyle(LabelTextSize size, bool bold) {
    switch (size) {
      case LabelTextSize.small:
        return _monospace(10, bold ? FontWeight.w700 : FontWeight.w400)
            .copyWith(color: AppColors.textSecondary);
      case LabelTextSize.normal:
        return _monospace(12, bold ? FontWeight.w800 : FontWeight.w500);
      case LabelTextSize.large:
        return _monospace(19, FontWeight.w900).copyWith(letterSpacing: 0.5);
      case LabelTextSize.xlarge:
        return _monospace(23, FontWeight.w900).copyWith(letterSpacing: 0.5);
    }
  }

  TextStyle _monospace(double size, FontWeight weight) => TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Courier', 'RobotoMono'],
        fontSize: size,
        fontWeight: weight,
        color: Colors.black,
        height: 1.25,
      );
}
