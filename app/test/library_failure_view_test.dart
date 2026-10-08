import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/presentation/library_failure_view.dart';
import 'package:material_ui/material_ui.dart';

final class _UntrustedFailure {
  int strings = 0;
  @override
  String toString() {
    strings++;
    throw StateError('Do not stringify an unknown failure.');
  }
}

void main() {
  testWidgets(
    'UT-093 failed open offers data preservation and retry without reset',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryFailureView(
              error: const LibraryOpenException('资料库格式更新，请使用兼容版本。'),
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      expect(find.text('资料库格式更新，请使用兼容版本。'), findsOneWidget);
      await tester.tap(find.text('数据保全与恢复说明'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('请保留完整资料库目录'), findsOneWidget);
      expect(find.textContaining('不生成业务备份或自动修复'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重置图库'), findsNothing);
      await tester.tap(find.text('重试打开'));
      expect(retries, 1);
    },
  );

  testWidgets(
    'UT-093/096 query failure does not claim a closed library or stringify',
    (tester) async {
      final error = _UntrustedFailure();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryFailureView(error: error, onRetry: () {}),
          ),
        ),
      );
      expect(find.text('图库打开失败'), findsOneWidget);
      expect(find.textContaining('现有数据已保留'), findsOneWidget);
      expect(find.text('数据保全与恢复说明'), findsNothing);
      expect(find.textContaining('已停止使用它'), findsNothing);
      expect(error.strings, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
