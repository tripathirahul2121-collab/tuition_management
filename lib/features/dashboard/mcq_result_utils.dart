import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/academic_catalog.dart';

class McqComputedResult {
  const McqComputedResult({
    required this.raw,
    required this.mobile,
    required this.studentName,
    required this.score,
    required this.correctCount,
    required this.wrongCount,
    required this.unansweredCount,
    required this.totalQuestions,
    required this.totalMarks,
    required this.timeTakenSeconds,
  });

  final Map<String, dynamic> raw;
  final String mobile;
  final String studentName;
  final double score;
  final int correctCount;
  final int wrongCount;
  final int unansweredCount;
  final int totalQuestions;
  final double totalMarks;
  final int timeTakenSeconds;

  double get percentage {
    if (totalMarks <= 0) return 0;
    return (score / totalMarks) * 100;
  }
}

class TuitionTopperEntry {
  const TuitionTopperEntry({
    required this.mobile,
    required this.name,
    required this.className,
    required this.toppedCount,
    required this.totalTopPercentage,
    required this.bestTopPercentage,
    required this.latestTopAt,
    required this.latestChapter,
  });

  final String mobile;
  final String name;
  final String className;
  final int toppedCount;
  final double totalTopPercentage;
  final double bestTopPercentage;
  final DateTime latestTopAt;
  final String latestChapter;

  double get averageTopPercentage =>
      toppedCount <= 0 ? 0 : totalTopPercentage / toppedCount;

  TuitionTopperEntry copyWith({
    int? toppedCount,
    double? totalTopPercentage,
    double? bestTopPercentage,
    DateTime? latestTopAt,
    String? latestChapter,
  }) {
    return TuitionTopperEntry(
      mobile: mobile,
      name: name,
      className: className,
      toppedCount: toppedCount ?? this.toppedCount,
      totalTopPercentage: totalTopPercentage ?? this.totalTopPercentage,
      bestTopPercentage: bestTopPercentage ?? this.bestTopPercentage,
      latestTopAt: latestTopAt ?? this.latestTopAt,
      latestChapter: latestChapter ?? this.latestChapter,
    );
  }
}

class McqReviewQuestion {
  const McqReviewQuestion({
    required this.question,
    required this.selectedIndex,
  });

  final Map<String, dynamic> question;
  final int? selectedIndex;
}

McqComputedResult computeMcqResult(
  Map<String, dynamic> testData,
  Map<String, dynamic> resultData,
) {
  final questions = mcqQuestionsFrom(testData);
  final answers = mcqAnswersFrom(resultData["answers"]);
  final questionOrder = mcqQuestionOrderFrom(
    resultData["questionOrder"],
    questions.length,
  );
  final marksPerQuestion =
      double.tryParse(testData["marksPerQuestion"]?.toString() ?? "") ?? 1;
  final negativeMarks =
      double.tryParse(testData["negativeMarksPerQuestion"]?.toString() ?? "") ??
      0;

  var correctCount = 0;
  var wrongCount = 0;

  for (
    var displayIndex = 0;
    displayIndex < questionOrder.length;
    displayIndex++
  ) {
    final selected = answers[displayIndex];
    if (selected == null) continue;

    final originalIndex = questionOrder[displayIndex];
    if (originalIndex < 0 || originalIndex >= questions.length) continue;

    final correctIndex =
        int.tryParse(
          questions[originalIndex]["correctIndex"]?.toString() ?? "",
        ) ??
        0;
    if (selected == correctIndex) {
      correctCount++;
    } else {
      wrongCount++;
    }
  }

  final totalQuestions = questions.length;
  final score =
      (correctCount * marksPerQuestion) - (wrongCount * negativeMarks);
  final storedTotalMarks =
      double.tryParse(testData["totalMarks"]?.toString() ?? "") ??
      double.tryParse(resultData["totalMarks"]?.toString() ?? "") ??
      0;
  final inferredTotalMarks = totalQuestions * marksPerQuestion;

  return McqComputedResult(
    raw: resultData,
    mobile: resultData["mobile"]?.toString() ?? "",
    studentName: resultData["studentName"]?.toString() ?? "Student",
    score: score,
    correctCount: correctCount,
    wrongCount: wrongCount,
    unansweredCount: totalQuestions - correctCount - wrongCount,
    totalQuestions: totalQuestions,
    totalMarks: storedTotalMarks > 0 ? storedTotalMarks : inferredTotalMarks,
    timeTakenSeconds: mcqTimeTakenSecondsFrom(resultData["timeTakenSeconds"]),
  );
}

Future<List<TuitionTopperEntry>> loadTuitionToppers() async {
  final classes = AcademicCatalog.classValues
      .where((className) => (int.tryParse(className) ?? 0) >= 6)
      .toList();
  final entriesByClassAndMobile = <String, TuitionTopperEntry>{};

  await Future.wait(
    classes.map(
      (className) =>
          _loadReportCardToppersForClass(className, entriesByClassAndMobile),
    ),
  );

  final testsSnap = await FirebaseFirestore.instance
      .collection("mcq_tests")
      .where("status", isEqualTo: "released")
      .get();

  await Future.wait(
    testsSnap.docs.map((testDoc) async {
      final testData = testDoc.data();
      final testClass = AcademicCatalog.mcqTargetClass(testData, fallback: "");
      if (!classes.contains(testClass)) return;

      final resultsSnap = await testDoc.reference
          .collection("results")
          .orderBy("score", descending: true)
          .orderBy("timeTakenSeconds")
          .orderBy("submittedAt")
          .limit(200)
          .get();
      if (resultsSnap.docs.isEmpty) return;

      final results =
          resultsSnap.docs
              .map(
                (doc) => (
                  docId: doc.id,
                  result: computeMcqResult(testData, doc.data()),
                ),
              )
              .toList()
            ..sort((a, b) => compareMcqComputedResults(a.result, b.result));
      if (results.isEmpty) return;

      final topPercentage = results.first.result.percentage;
      final toppedAt = mcqScheduledAt(testData);
      final chapter = testData["chapterName"]?.toString() ?? "MCQ Test";

      for (final item in results.where(
        (item) => (item.result.percentage - topPercentage).abs() < 0.0001,
      )) {
        final result = item.result;
        final mobile = result.mobile.isEmpty ? item.docId : result.mobile;
        final className =
            result.raw["class"]?.toString().trim().isNotEmpty == true
            ? result.raw["class"].toString()
            : testClass;
        _addTuitionTopper(
          entriesByClassAndMobile,
          className: className,
          mobile: mobile,
          name: result.studentName,
          percentage: result.percentage,
          toppedAt: toppedAt,
          chapter: chapter,
        );
      }
    }),
  );

  final entries = entriesByClassAndMobile.values.toList()
    ..sort((a, b) {
      final classCompare = _compareClassNames(a.className, b.className);
      if (classCompare != 0) return classCompare;
      return compareTuitionTopperEntries(a, b);
    });

  return entries;
}

Future<void> _loadReportCardToppersForClass(
  String className,
  Map<String, TuitionTopperEntry> entriesByClassAndMobile,
) async {
  final studentsSnap = await FirebaseFirestore.instance
      .collection("users")
      .where("role", isEqualTo: "student")
      .where("class", isEqualTo: className)
      .get();
  final studentDirectory = <String, String>{
    for (final doc in studentsSnap.docs)
      doc.id: _safeTopperName(doc.data()["name"]?.toString()),
  };
  final subjects = await AcademicCatalog.loadSubjectsForClass(className);

  final progressQueries = [
    for (final batch in AcademicCatalog.batchValues)
      for (final subject in subjects)
        (
          batch: batch,
          subject: subject,
          snap: FirebaseFirestore.instance
              .collection("progress")
              .doc(AcademicCatalog.batchDocId(className, batch))
              .collection(subject)
              .get(),
        ),
  ];
  final progressSnaps = await Future.wait(
    progressQueries.map((query) => query.snap),
  );

  for (var queryIndex = 0; queryIndex < progressQueries.length; queryIndex++) {
    final batch = progressQueries[queryIndex].batch;
    final subject = progressQueries[queryIndex].subject;
    for (final doc in progressSnaps[queryIndex].docs) {
      final data = doc.data();
      final totalMarks =
          double.tryParse(data["totalMarks"]?.toString() ?? "") ?? 0;
      if (totalMarks <= 0) continue;

      final studentsRaw = data["students"];
      final studentMap = studentsRaw is Map
          ? Map<String, dynamic>.from(studentsRaw)
          : <String, dynamic>{};
      final appeared =
          studentMap.entries
              .map((entry) {
                final value = entry.value;
                if (_isTopperAbsent(value)) return null;
                final marks = _topperMarksOf(value);
                return (
                  mobile: entry.key,
                  name: _studentNameFromReportCardValue(
                    value,
                    entry.key,
                    studentDirectory,
                  ),
                  percentage: (marks / totalMarks) * 100,
                  marks: marks,
                );
              })
              .whereType<
                ({String mobile, String name, double percentage, double marks})
              >()
              .toList()
            ..sort((a, b) {
              final percentCompare = b.percentage.compareTo(a.percentage);
              if (percentCompare != 0) return percentCompare;
              final marksCompare = b.marks.compareTo(a.marks);
              if (marksCompare != 0) return marksCompare;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

      if (appeared.isEmpty) continue;
      final topPercentage = appeared.first.percentage;
      final testDate = _reportCardTestDate(data["date"], doc.id);
      final chapter = data["chapter"]?.toString().trim();
      final testName =
          "${chapter?.isNotEmpty == true ? chapter : "Test"} • $subject"
          "${batch == AcademicCatalog.homeTuitionBatch ? " • Home Tuition" : ""}";

      for (final topper in appeared.where(
        (entry) => (entry.percentage - topPercentage).abs() < 0.0001,
      )) {
        _addTuitionTopper(
          entriesByClassAndMobile,
          className: className,
          mobile: topper.mobile,
          name: topper.name,
          percentage: topper.percentage,
          toppedAt: testDate,
          chapter: testName,
        );
      }
    }
  }
}

void _addTuitionTopper(
  Map<String, TuitionTopperEntry> entriesByClassAndMobile, {
  required String className,
  required String mobile,
  required String name,
  required double percentage,
  required DateTime toppedAt,
  required String chapter,
}) {
  final key = "$className|$mobile";
  final existing = entriesByClassAndMobile[key];

  if (existing == null) {
    entriesByClassAndMobile[key] = TuitionTopperEntry(
      mobile: mobile,
      name: name,
      className: className,
      toppedCount: 1,
      totalTopPercentage: percentage,
      bestTopPercentage: percentage,
      latestTopAt: toppedAt,
      latestChapter: chapter,
    );
    return;
  }

  final isLatest = toppedAt.isAfter(existing.latestTopAt);
  entriesByClassAndMobile[key] = existing.copyWith(
    toppedCount: existing.toppedCount + 1,
    totalTopPercentage: existing.totalTopPercentage + percentage,
    bestTopPercentage: percentage > existing.bestTopPercentage
        ? percentage
        : existing.bestTopPercentage,
    latestTopAt: isLatest ? toppedAt : existing.latestTopAt,
    latestChapter: isLatest ? chapter : existing.latestChapter,
  );
}

List<McqReviewQuestion> teacherOrderedReviewQuestions(
  Map<String, dynamic> testData,
  Map<String, dynamic> resultData,
) {
  final questions = mcqQuestionsFrom(testData);
  final answers = mcqAnswersFrom(resultData["answers"]);
  final questionOrder = mcqQuestionOrderFrom(
    resultData["questionOrder"],
    questions.length,
  );
  final displayIndexByOriginalIndex = <int, int>{};

  for (
    var displayIndex = 0;
    displayIndex < questionOrder.length;
    displayIndex++
  ) {
    displayIndexByOriginalIndex[questionOrder[displayIndex]] = displayIndex;
  }

  return questions.asMap().entries.map((entry) {
    final displayIndex = displayIndexByOriginalIndex[entry.key] ?? entry.key;
    return McqReviewQuestion(
      question: entry.value,
      selectedIndex: answers[displayIndex],
    );
  }).toList();
}

List<Map<String, dynamic>> mcqQuestionsFrom(Map<String, dynamic> testData) {
  final rawQuestions = testData["questions"];
  if (rawQuestions is! List) return const [];

  return rawQuestions
      .whereType<Map>()
      .map((question) => Map<String, dynamic>.from(question))
      .toList();
}

Map<int, int> mcqAnswersFrom(dynamic rawAnswers) {
  if (rawAnswers is! Map) return const {};

  return rawAnswers.map((key, value) {
    final questionIndex = int.tryParse(key.toString()) ?? -1;
    final selectedIndex = int.tryParse(value.toString()) ?? -1;
    return MapEntry(questionIndex, selectedIndex);
  })..removeWhere((key, value) => key < 0 || value < 0);
}

List<int> mcqQuestionOrderFrom(dynamic rawQuestionOrder, int questionCount) {
  final defaultOrder = List.generate(questionCount, (index) => index);
  if (rawQuestionOrder is! List) return defaultOrder;

  final order = rawQuestionOrder
      .map((value) => int.tryParse(value.toString()) ?? -1)
      .toList();
  if (order.length != questionCount) return defaultOrder;
  if (order.any((index) => index < 0 || index >= questionCount)) {
    return defaultOrder;
  }

  return order;
}

int compareMcqComputedResults(McqComputedResult a, McqComputedResult b) {
  final percentageCompare = b.percentage.compareTo(a.percentage);
  if (percentageCompare != 0) return percentageCompare;
  final scoreCompare = b.score.compareTo(a.score);
  if (scoreCompare != 0) return scoreCompare;
  final timeCompare = a.timeTakenSeconds.compareTo(b.timeTakenSeconds);
  if (timeCompare != 0) return timeCompare;
  final nameCompare = a.studentName.toLowerCase().compareTo(
    b.studentName.toLowerCase(),
  );
  if (nameCompare != 0) return nameCompare;
  return a.mobile.compareTo(b.mobile);
}

int compareTuitionTopperEntries(TuitionTopperEntry a, TuitionTopperEntry b) {
  final countCompare = b.toppedCount.compareTo(a.toppedCount);
  if (countCompare != 0) return countCompare;
  final percentageCompare = b.averageTopPercentage.compareTo(
    a.averageTopPercentage,
  );
  if (percentageCompare != 0) return percentageCompare;
  final bestCompare = b.bestTopPercentage.compareTo(a.bestTopPercentage);
  if (bestCompare != 0) return bestCompare;
  final dateCompare = b.latestTopAt.compareTo(a.latestTopAt);
  if (dateCompare != 0) return dateCompare;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int _compareClassNames(String a, String b) {
  final aClass = int.tryParse(a) ?? 999;
  final bClass = int.tryParse(b) ?? 999;
  final classCompare = aClass.compareTo(bClass);
  if (classCompare != 0) return classCompare;
  return a.compareTo(b);
}

bool _isTopperAbsent(dynamic value) {
  if (value is Map) {
    return value["absent"] == true || value["status"]?.toString() == "absent";
  }
  return false;
}

double _topperMarksOf(dynamic value) {
  if (value is Map) {
    return double.tryParse(value["marks"]?.toString() ?? "0") ?? 0;
  }
  return double.tryParse(value?.toString() ?? "0") ?? 0;
}

String _studentNameFromReportCardValue(
  dynamic value,
  String mobile,
  Map<String, String> studentDirectory,
) {
  if (value is Map) {
    final name = value["name"]?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
  }

  return studentDirectory[mobile] ?? "Student";
}

String _safeTopperName(String? value, {String fallback = "Student"}) {
  final trimmed = value?.trim() ?? "";
  return trimmed.isEmpty ? fallback : trimmed;
}

DateTime _reportCardTestDate(dynamic value, String fallbackId) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;

  final parts = fallbackId.split("-");
  if (parts.length == 3) {
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day != null && month != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  return DateTime(2000);
}

int mcqTimeTakenSecondsFrom(dynamic value) {
  return int.tryParse(value?.toString() ?? "") ?? (1 << 30);
}

DateTime mcqScheduledAt(Map<String, dynamic> testData) {
  final scheduledAt = testData["scheduledAt"];
  if (scheduledAt is Timestamp) return scheduledAt.toDate();
  if (scheduledAt is DateTime) return scheduledAt;
  return DateTime(2000);
}

DateTime mcqEndsAt(Map<String, dynamic> testData) {
  final totalTimeMinutes =
      int.tryParse(testData["totalTimeMinutes"]?.toString() ?? "") ?? 0;
  return mcqScheduledAt(testData).add(Duration(minutes: totalTimeMinutes));
}

bool isMcqTestEnded(Map<String, dynamic> testData, [DateTime? now]) {
  final totalTimeMinutes =
      int.tryParse(testData["totalTimeMinutes"]?.toString() ?? "") ?? 0;
  if (totalTimeMinutes <= 0) return false;
  return !(now ?? DateTime.now()).isBefore(mcqEndsAt(testData));
}
