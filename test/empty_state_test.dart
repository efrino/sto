import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/widgets/empty_state.dart';

void main() {
  /// Ukuran ini persis kondisi yang bikin overflow di HP: keyboard naik di
  /// halaman pencarian, tinggi sisa 221.5px sementara isi EmptyState butuh
  /// sekitar 265px.
  Widget bungkus(Widget child, {double width = 296, double height = 221.5}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  const isi = EmptyState(
    icon: Icons.search_off,
    title: 'Part tidak ditemukan',
    message: 'Coba kata kunci lain, atau perbarui master part dari server '
        'lewat tombol di kanan atas.',
    actionLabel: 'Perbarui master',
  );

  testWidgets('tidak overflow saat ruang tersisa sempit (keyboard naik)',
      (tester) async {
    await tester.pumpWidget(bungkus(isi));
    expect(tester.takeException(), isNull);
  });

  testWidgets('masih tampil utuh di ruang sempit - digulung, bukan terpotong',
      (tester) async {
    await tester.pumpWidget(bungkus(isi));

    expect(find.text('Part tidak ditemukan'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('tetap di tengah saat ruangnya lega', (tester) async {
    await tester.pumpWidget(bungkus(isi, height: 800));
    expect(tester.takeException(), isNull);

    final layar = tester.getRect(find.byType(SingleChildScrollView));
    final kolom = tester.getRect(find.byType(Column).first);
    final selisihAtas = kolom.top - layar.top;
    final selisihBawah = layar.bottom - kolom.bottom;

    // Jarak atas dan bawah kira-kira sama = isinya benar-benar di tengah.
    expect((selisihAtas - selisihBawah).abs(), lessThan(1));
  });
}
