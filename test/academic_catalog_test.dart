import 'package:flutter_test/flutter_test.dart';
import 'package:tuition/core/constants/academic_catalog.dart';

void main() {
  group('MCQ class mapping', () {
    test('keeps Vocabulary-1 in class 5', () {
      expect(AcademicCatalog.mcqClassForChapter('Vocabulary-1'), '5');
    });

    test('moves Mindful Eating to class 6', () {
      expect(AcademicCatalog.mcqClassForChapter('Mindful Eating'), '6');
    });

    test('moves acid base and neutral chapters to class 7', () {
      expect(AcademicCatalog.mcqClassForChapter('Acid Base and Neutral'), '7');
      expect(
        AcademicCatalog.mcqTargetClass({
          'chapterName': 'Acid, Base and Neutral',
          'class': '5',
        }),
        '7',
      );
    });
  });

  group('batch matching', () {
    test('home tuition MCQ updates do not match regular batch', () {
      expect(
        AcademicCatalog.updateBatchMatches({
          'type': 'mcq_test',
          'targetBatch': AcademicCatalog.homeTuitionBatch,
        }, AcademicCatalog.regularBatch),
        isFalse,
      );
    });

    test('legacy home MCQ tests do not match regular batch', () {
      expect(
        AcademicCatalog.mcqBatchMatches({
          'testLocation': 'home',
        }, AcademicCatalog.regularBatch),
        isFalse,
      );
    });
  });
}
