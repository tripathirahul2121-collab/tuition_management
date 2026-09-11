import 'package:cloud_firestore/cloud_firestore.dart';

class AcademicCatalog {
  const AcademicCatalog._();

  static final Map<String, Future<List<String>>> _subjectsFutureCache = {};

  static const allClassesTarget = 'all';
  static const regularBatch = 'regular';
  static const homeTuitionBatch = 'home_tuition';

  static const classValues = ['5', '6', '7', '8', '9', '10', '11', '12'];
  static const activeBatchValues = [regularBatch];
  static const batchValues = [regularBatch, homeTuitionBatch];

  static const updateTargets = [allClassesTarget, ...classValues];

  static String classLabel(String value) {
    if (value == allClassesTarget) return 'All Classes';
    if (value == 'junior') return 'Class 5';
    return 'Class $value';
  }

  static String batchLabel(String value) {
    if (value == homeTuitionBatch) return 'Home Tuition';
    return 'Regular Batch';
  }

  static String normalizeBatch(String? value) {
    return value == homeTuitionBatch ? homeTuitionBatch : regularBatch;
  }

  static String mcqTargetBatch(Map<String, dynamic> data) {
    final explicitBatch = data['targetBatch']?.toString();
    if (explicitBatch != null && explicitBatch.isNotEmpty) {
      return normalizeBatch(explicitBatch);
    }

    return data['testLocation']?.toString() == 'home'
        ? homeTuitionBatch
        : regularBatch;
  }

  static bool mcqBatchMatches(Map<String, dynamic> data, String selectedBatch) {
    return mcqTargetBatch(data) == normalizeBatch(selectedBatch);
  }

  static String? mcqClassForChapter(String? chapterName) {
    final normalized = _normalizedChapterKey(chapterName);
    if (normalized.isEmpty) return null;

    if (normalized == 'vocabulary1') return '5';
    if (normalized == 'mindfuleating') return '6';
    if (normalized.contains('acid') &&
        normalized.contains('base') &&
        normalized.contains('neutral')) {
      return '7';
    }

    return null;
  }

  static String mcqTargetClass(
    Map<String, dynamic> data, {
    String fallback = allClassesTarget,
  }) {
    final chapterClass = mcqClassForChapter(data['chapterName']?.toString());
    if (chapterClass != null) return chapterClass;

    final explicitClass = data['class']?.toString();
    if (explicitClass != null && explicitClass.isNotEmpty) return explicitClass;

    return fallback;
  }

  static bool updateBatchMatches(
    Map<String, dynamic> data,
    String selectedBatch,
  ) {
    final targetBatch = data['targetBatch']?.toString();
    if (targetBatch == null || targetBatch.isEmpty) {
      return data['type']?.toString() != 'mcq_test';
    }

    return normalizeBatch(targetBatch) == normalizeBatch(selectedBatch);
  }

  static bool batchMatches(Map<String, dynamic> data, String selectedBatch) {
    return normalizeBatch(data['batch']?.toString()) ==
        normalizeBatch(selectedBatch);
  }

  static String batchDocId(String className, String batch) {
    final normalizedBatch = normalizeBatch(batch);
    if (normalizedBatch == regularBatch) return className;
    return '${className}_$normalizedBatch';
  }

  static List<String> baseSubjectsForClass(String className) {
    if (className == '5' || className == 'junior') {
      return ['Maths', 'English', 'EVS'];
    }

    final cls = int.tryParse(className) ?? 6;

    if (cls >= 11) {
      return [
        'Maths',
        'Physics',
        'Chemistry',
        'Biology',
        'Accounts',
        'Economics',
        'Business Studies',
      ];
    }

    return ['Maths', 'Science', 'English', 'Social Science'];
  }

  static List<String> subjectsWithCustom(
    String className,
    Map<String, dynamic>? data,
  ) {
    final custom = data?['subjects'];
    final customSubjects = custom is List
        ? custom
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
        : const Iterable<String>.empty();

    return {...baseSubjectsForClass(className), ...customSubjects}.toList()
      ..sort();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> customSubjectsStream(
    String className,
  ) {
    return FirebaseFirestore.instance
        .collection('custom_subjects')
        .doc(className)
        .snapshots();
  }

  static Future<List<String>> loadSubjectsForClass(String className) async {
    final cached = _subjectsFutureCache[className];
    if (cached != null) return cached;

    final future = _fetchSubjectsForClass(className);
    _subjectsFutureCache[className] = future;
    return future;
  }

  static void clearSubjectsCache([String? className]) {
    if (className == null) {
      _subjectsFutureCache.clear();
    } else {
      _subjectsFutureCache.remove(className);
    }
  }

  static Future<List<String>> _fetchSubjectsForClass(String className) async {
    final doc = await FirebaseFirestore.instance
        .collection('custom_subjects')
        .doc(className)
        .get();

    return subjectsWithCustom(className, doc.data());
  }

  static String _normalizedChapterKey(String? value) {
    return (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
