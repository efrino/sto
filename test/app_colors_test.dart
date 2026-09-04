import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/theme/app_colors.dart';
import 'package:sto_prep/core/theme/app_theme.dart';

/// Aturan warna aplikasi: biru yang memimpin, merah hanya aksen, dan tidak
/// ada hijau maupun kuning sama sekali.
///
/// Diuji karena mudah bocor lagi tanpa sengaja - satu konstanta diganti,
/// seluruh layar bisa kembali terbaca seperti sedang error.
void main() {
  /// Warna dengan nama, supaya pesan gagalnya menyebut yang mana.
  const palet = <String, Color>{
    'primary': AppColors.primary,
    'primaryDark': AppColors.primaryDark,
    'primarySoft': AppColors.primarySoft,
    'accent': AppColors.accent,
    'accentSoft': AppColors.accentSoft,
    'navy': AppColors.navy,
    'navySoft': AppColors.navySoft,
    'success': AppColors.success,
    'successSoft': AppColors.successSoft,
    'warning': AppColors.warning,
    'warningSoft': AppColors.warningSoft,
    'danger': AppColors.danger,
    'dangerSoft': AppColors.dangerSoft,
    'info': AppColors.info,
    'infoSoft': AppColors.infoSoft,
    'background': AppColors.background,
    'border': AppColors.border,
  };

  double hue(Color c) => HSLColor.fromColor(c).hue;
  double saturation(Color c) => HSLColor.fromColor(c).saturation;

  group('Palet warna', () {
    test('tidak ada hijau maupun kuning di seluruh palet', () {
      palet.forEach((nama, warna) {
        // Warna nyaris abu-abu tidak terbaca sebagai "hijau" atau "kuning",
        // jadi tidak perlu dinilai.
        if (saturation(warna) < 0.15) return;

        final h = hue(warna);
        expect(
          h >= 45 && h <= 160,
          isFalse,
          reason: '$nama berada di rentang kuning-hijau (hue ${h.round()})',
        );
      });
    });

    test('warna utama biru, bukan merah', () {
      final h = hue(AppColors.primary);
      expect(h, greaterThan(190));
      expect(h, lessThan(250));

      // Yang paling sering salah: AppBar memakai warna utama, jadi warna
      // utama yang merah membuat seluruh layar terbaca sebagai error.
      expect(AppTheme.light.appBarTheme.backgroundColor, AppColors.primary);
    });

    test('merah perusahaan tetap ada, tapi sebagai aksen', () {
      expect(AppColors.accent, const Color(0xFFC8102E));

      // Merah hanya boleh muncul untuk keadaan gagal dan indikator tab -
      // bukan sebagai warna utama.
      expect(AppColors.danger, AppColors.accent);
      expect(AppColors.primary, isNot(AppColors.accent));
      expect(AppTheme.light.tabBarTheme.indicatorColor, AppColors.accent);
    });

    test('keadaan "beres" biru, "perlu perhatian" perunggu', () {
      expect(hue(AppColors.success), greaterThan(190));
      expect(hue(AppColors.success), lessThan(250));

      // Perunggu: rona oranye tua, bukan kuning terang.
      final hw = hue(AppColors.warning);
      expect(hw, greaterThan(15));
      expect(hw, lessThan(45));
      expect(HSLColor.fromColor(AppColors.warning).lightness, lessThan(0.45));
    });

    test('status masih bisa dibedakan satu sama lain', () {
      final status = {
        'success': AppColors.success,
        'warning': AppColors.warning,
        'danger': AppColors.danger,
        'navy': AppColors.navy,
      };
      expect(status.values.toSet(), hasLength(status.length));
    });
  });
}
