import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/features/home/widgets/teks_berjalan.dart';

/// Pita event di beranda.
///
/// Yang dijaga di sini bukan gerakannya, melainkan kapan gerakan itu TIDAK
/// terjadi: handheld lapangan bukan ponsel kencang, dan tulisan yang berjalan
/// terus-menerus padahal muat dibaca diam hanya memboroskan baterai.
void main() {
  const gaya = TextStyle(fontSize: 12);

  Widget bungkus(String teks, double lebar) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: lebar,
              child: TeksBerjalan(teks: teks, gaya: gaya),
            ),
          ),
        ),
      );

  testWidgets('teks yang muat ditampilkan diam, tanpa animasi', (t) async {
    await t.pumpWidget(bungkus('ALL CUSTOMER', 400));
    await t.pump(const Duration(milliseconds: 16));

    // Satu salinan saja - salinan kedua hanya dibuat untuk menyambung teks
    // yang sedang berjalan.
    expect(find.text('ALL CUSTOMER'), findsOneWidget);

    // pumpAndSettle akan gagal (timeout) bila ada animasi yang berputar
    // terus - jadi lolosnya panggilan ini adalah buktinya.
    await t.pumpAndSettle();
  });

  testWidgets('teks yang tidak muat berjalan dengan salinan penyambung',
      (t) async {
    const panjang = 'ALL CUSTOMER  -  06/09/2026 - 30/09/2026  -  Semua area '
        '-  Berlangsung, sisa 23 hari';

    await t.pumpWidget(bungkus(panjang, 120));
    await t.pump(const Duration(milliseconds: 16));

    // Dua salinan: yang sedang lewat, dan yang menyusul di belakangnya.
    // Jumlah salinan itulah tandanya: satu berarti diam, dua berarti
    // berjalan. Menghitung Transform tidak bisa dipakai - Scaffold sendiri
    // menyumbang beberapa.
    expect(find.text(panjang), findsNWidgets(2));
  });

  testWidgets('isi yang berganti dimulai dari awal lagi', (t) async {
    // Jadwal event berubah tiap hari. Tanpa penyetelan ulang, teks baru
    // masuk di tengah-tengah posisi teks lama dan terpotong aneh.
    await t.pumpWidget(bungkus('AAAA BBBB CCCC DDDD EEEE FFFF GGGG', 100));
    await t.pump(const Duration(seconds: 3));

    await t.pumpWidget(bungkus('HHHH IIII JJJJ KKKK LLLL MMMM NNNN', 100));
    await t.pump(const Duration(milliseconds: 16));

    expect(find.text('HHHH IIII JJJJ KKKK LLLL MMMM NNNN'), findsNWidgets(2));
    expect(find.textContaining('AAAA'), findsNothing);
  });
}
