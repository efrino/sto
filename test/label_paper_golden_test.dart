import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sto_prep/core/config/app_config.dart';
import 'package:sto_prep/data/models/part_item.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/features/preview/widgets/label_paper.dart';
import 'package:sto_prep/services/printer/label_builder.dart';

/// Golden test layout kertas tag.
/// Jalankan `flutter test --update-goldens` setelah sengaja mengubah layout.
void main() {
  setUpAll(() async => initializeDateFormatting('id'));

  // Kertas tag lebih tinggi dari viewport default test (800x600),
  // jadi surface-nya diperbesar supaya seluruh label ikut terekam.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(800, 1800);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  const part = PartItem(
    partNumber: '53801-BZ010',
    jobNumber: 'JOB-2601',
    partName: 'PANEL SIDE OUTER RH',
    customer: 'ADM',
    model: 'AYLA',
    area: 'WAREHOUSE 1',
    location: 'RAK A-01',
    stdPack: 50,
  );

  final tag = StoTag.fromPart(
    part: part,
    tagNo: 'STO260902-000123',
    sequence: 123,
    batchId: 'BATCH-1',
    createdBy: '11223344',
    createdAt: DateTime(2026, 9, 2, 7, 45),
    note: 'Rak paling atas',
  );

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFF4F6FA),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      );

  testWidgets('preview tag draft', (tester) async {
    await tester.pumpWidget(
      wrap(
        LabelPaper(
          document: LabelBuilder.build(
            tag,
            paper: PaperSize.mm58,
            printedAt: DateTime(2026, 9, 2, 7, 45),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(LabelPaper),
      matchesGoldenFile('goldens/label_draft.png'),
    );
  });

  testWidgets('preview tag sudah dicetak', (tester) async {
    await tester.pumpWidget(
      wrap(
        LabelPaper(
          document: LabelBuilder.build(
            tag.copyWith(
              status: TagStatus.printed,
              printedAt: DateTime(2026, 9, 2, 7, 46),
            ),
            paper: PaperSize.mm58,
            printedAt: DateTime(2026, 9, 2, 7, 46),
          ),
          watermark: 'SUDAH DICETAK',
          watermarkColor: const Color(0xFF127C4B),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(LabelPaper),
      matchesGoldenFile('goldens/label_printed.png'),
    );
  });
}
