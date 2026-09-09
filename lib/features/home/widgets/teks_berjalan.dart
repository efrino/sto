import 'dart:async';

import 'package:flutter/material.dart';

/// Satu baris teks yang berjalan mendatar ketika isinya tidak muat.
///
/// Dipakai pita event di beranda. Tujuannya menghemat tinggi layar: keterangan
/// yang tadinya memakan kartu setinggi 70 piksel cukup jadi satu baris, supaya
/// operator melihat seluruh menunya tanpa menggulir.
///
/// Dua hal yang sengaja dijaga:
///
/// - **Tidak beranimasi bila teksnya muat.** Handheld di lapangan bukan ponsel
///   kencang, dan tulisan yang bergerak terus-menerus padahal bisa dibaca diam
///   hanya membuang tenaga baterai serta melelahkan mata.
/// - **Jeda di awal.** Teks berhenti sejenak sebelum mulai berjalan, supaya
///   bagian depannya - nama event - sempat terbaca lebih dulu.
class TeksBerjalan extends StatefulWidget {
  const TeksBerjalan({
    super.key,
    required this.teks,
    required this.gaya,
    this.kecepatan = 34,
    this.jeda = const Duration(seconds: 2),
    this.selaAntarUlangan = 56,
  });

  final String teks;
  final TextStyle gaya;

  /// Piksel per detik.
  final double kecepatan;

  /// Diam sejenak di awal sebelum berjalan.
  final Duration jeda;

  /// Jarak antara ujung teks dan awal salinannya.
  final double selaAntarUlangan;

  @override
  State<TeksBerjalan> createState() => _TeksBerjalanState();
}

class _TeksBerjalanState extends State<TeksBerjalan>
    with SingleTickerProviderStateMixin {
  /// Dibuat di initState, BUKAN `late final`.
  ///
  /// Dengan `late`, teks yang muat (dan karenanya tidak pernah beranimasi)
  /// membuat pengendali ini baru terbentuk saat dispose() memanggilnya - dan
  /// membuat Ticker pada widget yang sudah dilepas dari pohon adalah galat.
  late final AnimationController _kendali;

  @override
  void initState() {
    super.initState();
    _kendali = AnimationController(vsync: this);
  }

  double _lebarTeks = 0;
  double _lebarRuang = 0;
  bool _berjalan = false;

  /// Penanda jeda awal. Disimpan supaya bisa dibatalkan saat widget dibuang -
  /// timer yang tertinggal hidup akan menyalakan animasi pada widget yang
  /// sudah tidak ada.
  Timer? _tunda;

  @override
  void dispose() {
    _tunda?.cancel();
    _kendali.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TeksBerjalan lama) {
    super.didUpdateWidget(lama);
    // Isi yang berganti - mis. jadwal event berubah - dimulai dari awal lagi,
    // bukan melanjutkan dari posisi teks sebelumnya.
    if (lama.teks != widget.teks ||
        lama.gaya != widget.gaya ||
        lama.kecepatan != widget.kecepatan ||
        lama.selaAntarUlangan != widget.selaAntarUlangan) {
      _tunda?.cancel();
      _tunda = null;
      _kendali.stop();
      _kendali.value = 0;
      _berjalan = false;
      _teksTerukur = null;
      _gayaTerukur = null;
      _scalerTerukur = null;
    }
  }

  /// Lebar teks hasil ukuran terakhir, beserta isi yang diukurnya.
  ///
  /// Beranda membangun ulang dirinya cukup sering (ringkasan, badge pesan,
  /// penyegaran berkala). Mengukur ulang teks yang sama pada tiap pembangunan
  /// itu pekerjaan sia-sia, dan pada handheld ikut menyumbang tersendatnya
  /// animasi.
  String? _teksTerukur;
  TextStyle? _gayaTerukur;
  TextScaler? _scalerTerukur;
  double _hasilUkur = 0;

  double _ukurTeks(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = defaultStyle.merge(widget.gaya);
    final scaler = MediaQuery.textScalerOf(context);

    if (_teksTerukur == widget.teks &&
        _gayaTerukur == effectiveStyle &&
        _scalerTerukur == scaler) {
      return _hasilUkur;
    }

    final pelukis = TextPainter(
      text: TextSpan(text: widget.teks, style: effectiveStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();

    _teksTerukur = widget.teks;
    _gayaTerukur = effectiveStyle;
    _scalerTerukur = scaler;
    _hasilUkur = pelukis.width.ceilToDouble();
    return _hasilUkur;
  }

  void _aturJalan() {
    final perlu = _lebarTeks > _lebarRuang;

    if (!perlu) {
      if (_berjalan) {
        _tunda?.cancel();
        _tunda = null;
        _kendali.stop();
        _kendali.value = 0;
        _berjalan = false;
      }
      return;
    }

    final jarak = _lebarTeks + widget.selaAntarUlangan;
    final durasi = Duration(
      milliseconds: (jarak / widget.kecepatan * 1000).round(),
    );

    if (_berjalan) {
      if (_kendali.duration != durasi) {
        _kendali.duration = durasi;
        if (!_kendali.isAnimating && _tunda == null) {
          _kendali.repeat();
        }
      }
      return;
    }

    _berjalan = true;
    _kendali.duration = durasi;
    _tunda?.cancel();
    _tunda = Timer(widget.jeda, () {
      _tunda = null;
      if (!mounted || !_berjalan) return;
      _kendali.repeat();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, batas) {
        _lebarTeks = _ukurTeks(context);
        _lebarRuang = batas.maxWidth;

        // Keputusan jalan/diam diambil setelah bingkai ini selesai dibangun -
        // memulai animasi di tengah build() membuat Flutter membangun ulang
        // widget yang sedang dibangun.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _aturJalan();
        });

        if (_lebarTeks <= _lebarRuang) {
          return Text(
            widget.teks,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: widget.gaya,
          );
        }

        final jarak = _lebarTeks + widget.selaAntarUlangan;

        // Deretan teksnya dibangun SEKALI, lalu diserahkan ke AnimatedBuilder
        // lewat parameter `child`.
        //
        // RepaintBoundary menyimpannya sebagai satu lapisan gambar; yang
        // bergerak tiap bingkai tinggal lapisan itu, bukan hurufnya.
        final deretan = RepaintBoundary(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.teks,
                maxLines: 1,
                softWrap: false,
                style: widget.gaya,
              ),
              // Salinan kedua menyusul di belakangnya. Saat salinan pertama
              // sudah bergeser sejauh `jarak`, salinan kedua tepat berada di
              // titik awal salinan pertama - jadi saat hitungannya diulang
              // dari nol, gambarnya persis sama dan sambungannya tak terlihat.
              SizedBox(width: widget.selaAntarUlangan),
              Text(
                widget.teks,
                maxLines: 1,
                softWrap: false,
                style: widget.gaya,
              ),
            ],
          ),
        );

        return ClipRect(
          child: AnimatedBuilder(
            animation: _kendali,
            child: deretan,
            builder: (context, anak) {
              // OverflowBox melepas batas lebar dari induknya. Tanpa itu,
              // teksnya dipaksa selebar ruang yang tersedia lalu terpotong -
              // yang berjalan tinggal potongan pertamanya saja.
              return OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Transform.translate(
                  offset: Offset(-_kendali.value * jarak, 0),
                  child: anak,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
