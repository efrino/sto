import 'package:flutter/material.dart';

/// Palet warna korporat MAJ: biru sebagai warna utama, merah sebagai aksen.
///
/// Perbandingannya kira-kira 2/3 biru : 1/3 merah. Sebelumnya merah dipakai
/// sebagai warna utama (AppBar, tombol, ikon) dan akibatnya seluruh layar
/// terbaca seperti sedang error - padahal keadaannya normal. Merah sekarang
/// disimpan untuk hal yang memang perlu diwaspadai (gagal cetak, pembatalan)
/// dan untuk aksen identitas perusahaan.
///
/// Hijau dan kuning sengaja tidak dipakai sama sekali. Keadaan "beres"
/// memakai biru terang dan "perlu perhatian" memakai perunggu - keduanya
/// tetap bisa dibedakan tanpa warna lampu lalu lintas.
class AppColors {
  AppColors._();

  // -------------------------------------------------- utama (biru, 2/3)
  static const Color primary = Color(0xFF1A4E8A); // biru MAJ
  static const Color primaryDark = Color(0xFF123A69);
  static const Color primarySoft = Color(0xFFE8EFF8);

  // ------------------------------------------------- aksen (merah, 1/3)
  /// Merah MAJ. Pemakaiannya dibatasi: indikator tab, penanda aktif, dan
  /// keadaan yang benar-benar gagal - bukan latar layar atau tombol utama.
  static const Color accent = Color(0xFFC8102E);
  static const Color accentSoft = Color(0xFFFDE8EB);

  static const Color navy = Color(0xFF12294B);
  static const Color navySoft = Color(0xFFE7ECF4);

  static const Color background = Color(0xFFF4F6FA);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE1E5EC);

  static const Color textPrimary = Color(0xFF1B1F27);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9AA1AC);

  // ----------------------------------------------------------- keadaan
  /// "Beres" - biru terang, sengaja dibedakan dari [primary] yang lebih pekat
  /// supaya chip status tidak melebur dengan warna AppBar dan tombol.
  static const Color success = Color(0xFF1668B3);
  static const Color successSoft = Color(0xFFE6F0F9);

  /// "Perlu perhatian" - perunggu, bukan kuning.
  static const Color warning = Color(0xFF8A5A2B);
  static const Color warningSoft = Color(0xFFF6EDE4);

  /// "Gagal / dibatalkan" - merah MAJ, satu-satunya tempat merah tampil lebar.
  static const Color danger = accent;
  static const Color dangerSoft = accentSoft;

  static const Color info = Color(0xFF2563A5);
  static const Color infoSoft = Color(0xFFE6EEF7);
}
