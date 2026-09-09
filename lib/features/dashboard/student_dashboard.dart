import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';
import '../../core/services/firestore_query_cache.dart';
import 'mcq_result_utils.dart';

String _formatMcqScore(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  bool _checkedTodayAbsence = false;
  bool _checkedRemarks = false;
  Future<_LatestMcqResult?>? _latestMcqFuture;
  Future<_DashboardInsights>? _dashboardInsightsFuture;
  String? _latestMcqKey;
  String? _dashboardInsightsKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final userData =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (userData == null) return;

    final studentKey =
        "${userData["class"]?.toString() ?? ""}-${AcademicCatalog.normalizeBatch(userData["batch"]?.toString())}-${userData["mobile"]?.toString() ?? ""}";

    if (_latestMcqKey != studentKey) {
      _latestMcqKey = studentKey;
      _latestMcqFuture = _loadLatestMcqResult(userData);
    }

    if (_dashboardInsightsKey != studentKey) {
      _dashboardInsightsKey = studentKey;
      _dashboardInsightsFuture = _loadDashboardInsights(userData);
    }

    if (_checkedTodayAbsence) return;
    _checkedTodayAbsence = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTodayAbsencePromptIfNeeded(userData);
      _showUnreadRemarkPromptIfNeeded(userData);
    });
  }

  Future<void> _showTodayAbsencePromptIfNeeded(
    Map<String, dynamic> userData,
  ) async {
    final studentMobile = userData["mobile"]?.toString() ?? "";
    final studentClass = userData["class"]?.toString() ?? "";
    final studentBatch = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );

    if (studentMobile.isEmpty || studentClass.isEmpty) return;

    final todayKey = DateFormat("yyyy-MM-dd").format(DateTime.now());

    final doc = await FirebaseFirestore.instance
        .collection("attendance")
        .doc(AcademicCatalog.batchDocId(studentClass, studentBatch))
        .collection("records")
        .doc(todayKey)
        .get();

    if (!mounted || !doc.exists) return;

    final data = doc.data() ?? {};
    final isAbsent = data[studentMobile] == false;
    final reason = data["reason_$studentMobile"]?.toString().trim() ?? "";

    if (!isAbsent || reason.isNotEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Mention Why u are absent today."),
        content: const Text(
          "Your teacher has marked you absent today. Please submit your reason.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pushNamed(
                context,
                "/student-attendance",
                arguments: userData,
              );
            },
            child: const Text("Mention Reason"),
          ),
        ],
      ),
    );
  }

  DateTime _remarkDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime(2000);
  }

  Future<void> _showUnreadRemarkPromptIfNeeded(
    Map<String, dynamic> userData,
  ) async {
    if (_checkedRemarks) return;
    _checkedRemarks = true;

    final mobile = userData["mobile"]?.toString() ?? "";
    final className = userData["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final progressDocId = AcademicCatalog.batchDocId(className, batchName);

    if (mobile.isEmpty || className.isEmpty) return;

    _PendingRemark? latest;

    final generalFuture = FirebaseFirestore.instance
        .collection("teacher_remarks")
        .where("mobile", isEqualTo: mobile)
        .get();
    final subjects = await AcademicCatalog.loadSubjectsForClass(className);
    final progressFutures = subjects.map((subject) {
      return FirebaseFirestore.instance
          .collection("progress")
          .doc(progressDocId)
          .collection(subject)
          .get();
    }).toList();
    final generalSnap = await generalFuture;

    for (final doc in generalSnap.docs) {
      final data = doc.data();
      if (!AcademicCatalog.batchMatches(data, batchName)) continue;
      final readBy = data["readBy"];
      final alreadyRead =
          readBy is List && readBy.map((e) => e.toString()).contains(mobile);
      final text = data["remark"]?.toString().trim() ?? "";
      final hasRatings =
          data["homeworkEnabled"] == true ||
          data["classPerformanceEnabled"] == true;

      if (alreadyRead || (text.isEmpty && !hasRatings)) continue;

      final item = _PendingRemark(
        title: "New general remark",
        preview: text.isEmpty
            ? "Your teacher has shared today's ratings."
            : text,
        date: _remarkDate(data["createdAt"]),
        markRead: () => doc.reference.set({
          "readBy": FieldValue.arrayUnion([mobile]),
        }, SetOptions(merge: true)),
      );

      if (latest == null || item.date.isAfter(latest.date)) latest = item;
    }

    final progressSnaps = await Future.wait(progressFutures);
    for (final testsSnap in progressSnaps) {
      for (final doc in testsSnap.docs) {
        final data = doc.data();
        final studentsRaw = data["students"];
        if (studentsRaw is! Map<String, dynamic>) continue;

        final studentData = studentsRaw[mobile];
        if (studentData is! Map<String, dynamic>) continue;

        final feedback = studentData["feedback"]?.toString().trim() ?? "";
        final feedbackRead = studentData["feedbackRead"] == true;
        if (feedback.isEmpty || feedbackRead) continue;

        final item = _PendingRemark(
          title: "New test remark",
          preview: feedback,
          date: _remarkDate(data["date"]),
          markRead: () =>
              doc.reference.update({"students.$mobile.feedbackRead": true}),
        );

        if (latest == null || item.date.isAfter(latest.date)) latest = item;
      }
    }

    if (!mounted || latest == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(latest!.title),
        content: Text(latest.preview),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Later"),
          ),
          FilledButton(
            onPressed: () async {
              await latest!.markRead();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              Navigator.pushNamed(
                context,
                "/student-teacher-remarks",
                arguments: userData,
              );
            },
            child: const Text("View Remarks"),
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// DASHBOARD TILE
  ////////////////////////////////////////////////////////////

  Widget dashboardTile(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String route, {
    Object? arguments,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        Navigator.pushNamed(context, route, arguments: arguments);
      },
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white,
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              blurRadius: 24,
              offset: const Offset(0, 12),
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                  height: 1.12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget starsDashboardTile(
    BuildContext context,
    Map<String, dynamic> userData,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        Navigator.pushNamed(context, "/student-stars", arguments: userData);
      },
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFFFFFBEB),
          border: Border.all(color: const Color(0xFFFDE68A)),
          boxShadow: [
            BoxShadow(
              blurRadius: 24,
              offset: const Offset(0, 12),
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -18,
              child: Icon(
                Icons.workspace_premium,
                color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                size: 96,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Color(0xFFD97706),
                      size: 28,
                    ),
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Stars of ME",
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Top achievers",
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _latestUpdateStream(
    String className,
    String batchName,
  ) {
    final targets = className.isEmpty
        ? [AcademicCatalog.allClassesTarget]
        : [AcademicCatalog.allClassesTarget, className];

    return FirebaseFirestore.instance
        .collection("updates")
        .where("target", whereIn: targets)
        .where("scheduledAt", isLessThanOrEqualTo: Timestamp.now())
        .orderBy("scheduledAt", descending: true)
        .limit(QueryLimits.studentRecentUpdates)
        .snapshots();
  }

  Future<void> _markUpdateRead(String updateId, String mobile) async {
    if (mobile.isEmpty) return;

    await FirebaseFirestore.instance.collection("updates").doc(updateId).set({
      "readBy": FieldValue.arrayUnion([mobile]),
    }, SetOptions(merge: true));
  }

  Widget _latestAnnouncementCard(
    BuildContext context,
    Map<String, dynamic> userData,
  ) {
    final mobile = userData["mobile"]?.toString() ?? "";
    final className = userData["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );

    return StreamBuilder<QuerySnapshot>(
      stream: _latestUpdateStream(className, batchName),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final unreadDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final target =
              data["target"]?.toString() ?? AcademicCatalog.allClassesTarget;
          if (target != AcademicCatalog.allClassesTarget &&
              target != className) {
            return false;
          }
          if (!AcademicCatalog.updateBatchMatches(data, batchName)) {
            return false;
          }

          final readBy = data["readBy"];
          if (readBy is! List) return true;
          return !readBy.map((value) => value.toString()).contains(mobile);
        }).toList();

        if (unreadDocs.isEmpty) return const SizedBox.shrink();

        final doc = unreadDocs.first;
        final data = doc.data() as Map<String, dynamic>;
        final title = data["title"]?.toString() ?? "";
        final scheduledAt = (data["scheduledAt"] as Timestamp).toDate();

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await _markUpdateRead(doc.id, mobile);
            if (!context.mounted) return;
            Navigator.pushNamed(
              context,
              "/student-updates",
              arguments: userData,
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFC857), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB703).withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  height: 38,
                  width: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFFB703),
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "New Announcement",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        DateFormat("dd MMM • hh:mm a").format(scheduledAt),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
    );
  }

  Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
    for (var start = 0; start < items.length; start += size) {
      final end = (start + size) > items.length ? items.length : start + size;
      yield items.sublist(start, end);
    }
  }

  Future<_LatestMcqResult?> _loadLatestMcqResult(
    Map<String, dynamic> userData, {
    bool forceRefresh = false,
  }) {
    final mobile = userData["mobile"]?.toString() ?? "";
    final className = userData["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );

    return FirestoreQueryCache.remember(
      "student-latest-mcq:$className:$batchName:$mobile",
      () => _fetchLatestMcqResult(userData, forceRefresh: forceRefresh),
      forceRefresh: forceRefresh,
    );
  }

  Future<_LatestMcqResult?> _fetchLatestMcqResult(
    Map<String, dynamic> userData, {
    bool forceRefresh = false,
  }) async {
    final mobile = userData["mobile"]?.toString() ?? "";
    final className = userData["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    if (mobile.isEmpty || className.isEmpty) return null;

    final testsSnap = await FirestoreQueryCache.remember(
      "student-dashboard-mcq-tests:$className:$batchName",
      () => FirebaseFirestore.instance
          .collection("mcq_tests")
          .where("status", isEqualTo: "released")
          .orderBy("scheduledAt", descending: true)
          .limit(QueryLimits.studentDashboardMcqLookup)
          .get(),
      forceRefresh: forceRefresh,
    );
    var classTests = testsSnap.docs
        .where(
          (doc) =>
              AcademicCatalog.mcqTargetClass(doc.data()) == className &&
              AcademicCatalog.mcqBatchMatches(doc.data(), batchName),
        )
        .toList();

    var appeared = await _loadAppearedMcqResults(classTests, mobile);

    if (appeared.isEmpty &&
        QueryLimits.studentDashboardMcqLookup < QueryLimits.studentMcqTests) {
      final fallbackSnap = await FirestoreQueryCache.remember(
        "student-dashboard-mcq-tests-full:$className:$batchName",
        () => FirebaseFirestore.instance
            .collection("mcq_tests")
            .where("status", isEqualTo: "released")
            .orderBy("scheduledAt", descending: true)
            .limit(QueryLimits.studentMcqTests)
            .get(),
        forceRefresh: forceRefresh,
      );
      classTests = fallbackSnap.docs
          .where(
            (doc) =>
                AcademicCatalog.mcqTargetClass(doc.data()) == className &&
                AcademicCatalog.mcqBatchMatches(doc.data(), batchName),
          )
          .toList();
      appeared = await _loadAppearedMcqResults(classTests, mobile);
    }

    if (appeared.isEmpty) return null;
    appeared.sort((a, b) => b.date.compareTo(a.date));

    final latest = appeared.first;
    final latestTestData = classTests
        .firstWhere((doc) => doc.reference == latest.testReference)
        .data();
    final resultsSnap = await latest.testReference
        ?.collection("results")
        .orderBy("score", descending: true)
        .orderBy("timeTakenSeconds")
        .orderBy("submittedAt")
        .limit(QueryLimits.mcqPreviewResults)
        .get();
    if (resultsSnap == null) return latest;

    final ranking = resultsSnap.docs
        .map((doc) => computeMcqResult(latestTestData, doc.data()))
        .toList();
    final rankIndex = ranking.indexWhere((entry) => entry.mobile == mobile);

    return latest.copyWith(rank: rankIndex == -1 ? 0 : rankIndex + 1);
  }

  Future<List<_LatestMcqResult>> _loadAppearedMcqResults(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classTests,
    String mobile,
  ) async {
    final appeared = <_LatestMcqResult>[];

    for (final chunk in _chunks(classTests, 8)) {
      final resultPairs = await Future.wait(
        chunk.map((doc) async {
          final resultDoc = await doc.reference
              .collection("results")
              .doc(mobile)
              .get();
          return (testDoc: doc, resultDoc: resultDoc);
        }),
      );

      appeared.addAll(
        resultPairs.where((pair) => pair.resultDoc.exists).map((pair) {
          final testData = pair.testDoc.data();
          final resultData = pair.resultDoc.data() ?? {};
          final computed = computeMcqResult(testData, resultData);

          return _LatestMcqResult(
            title: testData["chapterName"]?.toString().trim().isEmpty == false
                ? testData["chapterName"].toString()
                : "MCQ Test",
            score: _formatMcqScore(computed.score),
            correct: computed.correctCount.toString(),
            wrong: computed.wrongCount.toString(),
            rank: 0,
            date: _remarkDate(
              resultData["submittedAt"] ?? testData["scheduledAt"],
            ),
            testReference: pair.testDoc.reference,
          );
        }),
      );

      if (appeared.isNotEmpty) break;
    }

    return appeared;
  }

  DateTime _testDate(dynamic value, String fallbackId) {
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

  double _marksOf(dynamic value) {
    if (value is! Map<String, dynamic>) return 0;
    return double.tryParse(value["marks"]?.toString() ?? "0") ?? 0;
  }

  bool _isAbsent(dynamic value) {
    if (value is! Map<String, dynamic>) return true;
    return value["absent"] == true ||
        value["marks"]?.toString().trim().toLowerCase() == "ab";
  }

  Future<_DashboardInsights> _loadDashboardInsights(
    Map<String, dynamic> userData, {
    bool forceRefresh = false,
  }) {
    final mobile = userData["mobile"]?.toString() ?? "";
    final className = userData["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final monthKey = DateFormat("yyyy-MM").format(DateTime.now());

    return FirestoreQueryCache.remember(
      "student-dashboard-insights:$className:$batchName:$mobile:$monthKey",
      () => _fetchDashboardInsights(userData),
      ttl: const Duration(minutes: 2),
      forceRefresh: forceRefresh,
    );
  }

  Future<_DashboardInsights> _fetchDashboardInsights(
    Map<String, dynamic> userData,
  ) async {
    final mobile = userData["mobile"]?.toString() ?? "";
    final className = userData["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final batchDocId = AcademicCatalog.batchDocId(className, batchName);

    if (mobile.isEmpty || className.isEmpty) {
      return _DashboardInsights.empty();
    }

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final startKey = DateFormat("yyyy-MM-dd").format(firstDay);
    final endKey = DateFormat("yyyy-MM-dd").format(lastDay);

    final attendanceFuture = FirebaseFirestore.instance
        .collection("attendance")
        .doc(batchDocId)
        .collection("records")
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: startKey,
          isLessThanOrEqualTo: endKey,
        )
        .get();

    final subjects = await AcademicCatalog.loadSubjectsForClass(className);
    final progressFutures = subjects.map((subject) {
      return FirebaseFirestore.instance
          .collection("progress")
          .doc(batchDocId)
          .collection(subject)
          .orderBy("date", descending: true)
          .limit(QueryLimits.dashboardProgressTestsPerSubject)
          .get();
    }).toList();

    final mcqFuture = FirebaseFirestore.instance
        .collection("mcq_tests")
        .where("status", isEqualTo: "released")
        .orderBy("scheduledAt", descending: true)
        .limit(QueryLimits.studentDashboardMcqLookup)
        .get();

    final progressSnaps = await Future.wait(progressFutures);
    final comparisons = <_ScoreComparison>[];

    for (var subjectIndex = 0; subjectIndex < subjects.length; subjectIndex++) {
      final subject = subjects[subjectIndex];
      final snap = progressSnaps[subjectIndex];

      for (final doc in snap.docs) {
        final data = doc.data();
        final studentsRaw = data["students"];
        if (studentsRaw is! Map<String, dynamic>) continue;

        final ownRecord = studentsRaw[mobile];
        if (_isAbsent(ownRecord)) continue;

        final totalMarks =
            double.tryParse(data["totalMarks"]?.toString() ?? "0") ?? 0;
        if (totalMarks <= 0) continue;

        final appearedMarks = studentsRaw.values
            .where((record) => !_isAbsent(record))
            .map(_marksOf)
            .toList();
        if (appearedMarks.isEmpty) continue;

        final ownMarks = _marksOf(ownRecord);
        final average =
            appearedMarks.fold<double>(0, (total, mark) => total + mark) /
            appearedMarks.length;

        final chapter = data["chapter"]?.toString().trim() ?? "";
        comparisons.add(
          _ScoreComparison(
            title: chapter.isEmpty ? subject : chapter,
            subject: subject,
            date: _testDate(data["date"], doc.id),
            studentMarks: ownMarks,
            averageMarks: average,
            totalMarks: totalMarks,
          ),
        );
      }
    }

    final mcqSnap = await mcqFuture;
    final classMcqDocs = mcqSnap.docs
        .where((doc) => AcademicCatalog.mcqTargetClass(doc.data()) == className)
        .toList();
    final ownMcqPairs = await Future.wait(
      classMcqDocs.map((doc) async {
        final resultDoc = await doc.reference
            .collection("results")
            .doc(mobile)
            .get();
        return (testDoc: doc, resultDoc: resultDoc);
      }),
    );
    final appearedMcqs = ownMcqPairs
        .where((pair) => pair.resultDoc.exists)
        .toList();

    for (var i = 0; i < appearedMcqs.length; i++) {
      final testDoc = appearedMcqs[i].testDoc;
      final testData = testDoc.data();
      final ownResultData = appearedMcqs[i].resultDoc.data() ?? {};
      final ownResult = computeMcqResult(testData, ownResultData);
      if (ownResult.totalMarks <= 0) continue;

      final appeared =
          int.tryParse(testData["submissionCount"]?.toString() ?? "") ?? 0;
      final totalSubmittedScore =
          double.tryParse(testData["totalSubmittedScore"]?.toString() ?? "") ??
          0.0;
      final average = appeared == 0
          ? ownResult.score
          : totalSubmittedScore / appeared;

      final chapterName = testData["chapterName"]?.toString().trim() ?? "";
      comparisons.add(
        _ScoreComparison(
          title: chapterName.isEmpty ? "MCQ Test" : chapterName,
          subject: "MCQ",
          date: _testDate(testData["scheduledAt"], testDoc.id),
          studentMarks: ownResult.score,
          averageMarks: average,
          totalMarks: ownResult.totalMarks,
        ),
      );
    }

    comparisons.sort((a, b) => b.date.compareTo(a.date));
    final recentComparisons = comparisons.take(5).toList().reversed.toList();

    final attendanceSnap = await attendanceFuture;
    var total = 0;
    var present = 0;
    var absent = 0;

    for (final doc in attendanceSnap.docs) {
      final data = doc.data();
      if (!data.containsKey(mobile)) continue;

      final status = data[mobile];
      if (status == true) {
        total++;
        present++;
      } else if (status == false) {
        total++;
        absent++;
      }
    }

    return _DashboardInsights(
      comparisons: recentComparisons,
      attendance: _AttendanceSummary(
        total: total,
        present: present,
        absent: absent,
        monthLabel: DateFormat("MMM yyyy").format(now),
      ),
    );
  }

  Widget _latestMcqResultCard(
    BuildContext context,
    Map<String, dynamic> userData,
  ) {
    final future = _latestMcqFuture;
    if (future == null) return const SizedBox.shrink();

    return FutureBuilder<_LatestMcqResult?>(
      future: future,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) return const SizedBox.shrink();
        final isTopper = result.isTopper;

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pushNamed(
              context,
              "/student-mcq-tests",
              arguments: userData,
            ),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isTopper
                    ? const Color(0xFFFFFBEB)
                    : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isTopper
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFFC7D2FE),
                  width: isTopper ? 1.4 : 1,
                ),
                boxShadow: isTopper
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.16),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: isTopper
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF4F46E5).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isTopper ? Icons.emoji_events : Icons.fact_check,
                      color: isTopper ? Colors.white : const Color(0xFF4338CA),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isTopper
                                ? const Color(0xFF92400E)
                                : const Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                            fontSize: isTopper ? 15 : 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${result.rankLabel} • Score ${result.score} • ${result.correct} correct • ${result.wrong} wrong",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isTopper
                                ? const Color(0xFFB45309)
                                : Colors.grey.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  Widget _premiumHeader(Map<String, dynamic> userData) {
    final name = userData["name"]?.toString().trim().isNotEmpty == true
        ? userData["name"].toString()
        : "Student";
    final classLabel = AcademicCatalog.classLabel(
      userData["class"]?.toString() ?? "",
    );
    final mobile = userData["mobile"]?.toString() ?? "";
    final school = userData["school"]?.toString().trim().isNotEmpty == true
        ? userData["school"].toString()
        : "School not added";
    final initials = name
        .trim()
        .split(RegExp(r"\s+"))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171717), Color(0xFF20352F)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF171717).withValues(alpha: 0.24),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6A241),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD6A241).withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.isEmpty ? "S" : initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ME Scholar Profile",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 10) / 2;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _profileDetail(
                      Icons.workspace_premium,
                      "Class",
                      classLabel,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _profileDetail(Icons.phone, "Mobile", mobile),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _profileDetail(Icons.school, "School", school),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _profileDetail(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFD6A241)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isEmpty ? "Not added" : value,
                  maxLines: label == "School" ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _analyticsSection(Map<String, dynamic> userData) {
    final future = _dashboardInsightsFuture;
    if (future == null) return const SizedBox.shrink();

    return FutureBuilder<_DashboardInsights>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _analyticsLoadingCard();
        }

        if (snapshot.hasError) {
          return _emptyAnalyticsCard(
            icon: Icons.insights,
            title: "Analytics unavailable",
            message: "Please check again after the latest records sync.",
          );
        }

        final insights = snapshot.data ?? _DashboardInsights.empty();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Performance Snapshot"),
            const SizedBox(height: 12),
            _marksComparisonCard(insights.comparisons, userData),
            const SizedBox(height: 14),
            _attendancePieCard(insights.attendance, userData),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF2A9D8F).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.analytics_rounded,
            color: Color(0xFF16786D),
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF141414),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _analyticsLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _premiumCardDecoration(),
      child: const Row(
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              "Preparing performance snapshot",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyAnalyticsCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _premiumCardDecoration(),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEF6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF596579)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF141414),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _premiumCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  Widget _marksComparisonCard(
    List<_ScoreComparison> comparisons,
    Map<String, dynamic> userData,
  ) {
    if (comparisons.isEmpty) {
      return _emptyAnalyticsCard(
        icon: Icons.bar_chart_rounded,
        title: "Marks comparison",
        message: "Released test scores will appear here.",
      );
    }

    final latest = comparisons.last;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.pushNamed(
        context,
        "/student-report-card",
        arguments: userData,
      ),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: _premiumCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Marks comparison",
                    style: TextStyle(
                      color: Color(0xFF141414),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _legendDot("You", const Color(0xFFD6A241)),
                const SizedBox(width: 10),
                _legendDot("Average", const Color(0xFF2A9D8F)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Latest: ${latest.title} • ${latest.studentScoreLabel} vs ${latest.averageScoreLabel}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: 100,
                  barGroups: comparisons.asMap().entries.map((entry) {
                    final item = entry.value;
                    return BarChartGroupData(
                      x: entry.key,
                      barsSpace: 5,
                      barRods: [
                        BarChartRodData(
                          toY: item.studentPercent.clamp(0, 100).toDouble(),
                          width: 9,
                          color: const Color(0xFFD6A241),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                        BarChartRodData(
                          toY: item.averagePercent.clamp(0, 100).toDouble(),
                          width: 9,
                          color: const Color(0xFF2A9D8F),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: const Color(0xFFE5E7EB),
                      strokeWidth: value == 0 ? 0 : 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: 25,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Text(
                            "${value.toInt()}%",
                            style: const TextStyle(
                              color: Color(0xFF8A92A3),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= comparisons.length) {
                            return const SizedBox.shrink();
                          }

                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            space: 8,
                            child: SizedBox(
                              width: 56,
                              child: Text(
                                comparisons[index].shortLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF596579),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: const Color(0xFF171717),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final item = comparisons[group.x.toInt()];
                        final label = rodIndex == 0 ? "You" : "Average";
                        final marks = rodIndex == 0
                            ? item.studentScoreLabel
                            : item.averageScoreLabel;
                        return BarTooltipItem(
                          "$label\n$marks",
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 8,
          width: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF596579),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _attendancePieCard(
    _AttendanceSummary attendance,
    Map<String, dynamic> userData,
  ) {
    final hasData = attendance.total > 0;
    final sections = hasData
        ? [
            PieChartSectionData(
              value: attendance.present.toDouble(),
              color: const Color(0xFF2A9D8F),
              radius: 24,
              showTitle: false,
            ),
            PieChartSectionData(
              value: attendance.absent.toDouble(),
              color: const Color(0xFFE76F51),
              radius: 24,
              showTitle: false,
            ),
          ]
        : [
            PieChartSectionData(
              value: 1,
              color: const Color(0xFFE5E7EB),
              radius: 24,
              showTitle: false,
            ),
          ];

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.pushNamed(
        context,
        "/student-attendance",
        arguments: userData,
      ),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: _premiumCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Attendance",
                    style: TextStyle(
                      color: Color(0xFF141414),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  attendance.monthLabel,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  height: 148,
                  width: 148,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: sections,
                          sectionsSpace: hasData ? 3 : 0,
                          centerSpaceRadius: 46,
                          startDegreeOffset: -90,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hasData ? "${attendance.percentLabel}%" : "--",
                            style: const TextStyle(
                              color: Color(0xFF141414),
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Present",
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    children: [
                      _attendanceMetric(
                        "Total",
                        attendance.total.toString(),
                        const Color(0xFF596579),
                      ),
                      const SizedBox(height: 10),
                      _attendanceMetric(
                        "Present",
                        attendance.present.toString(),
                        const Color(0xFF2A9D8F),
                      ),
                      const SizedBox(height: 10),
                      _attendanceMetric(
                        "Absent",
                        attendance.absent.toString(),
                        const Color(0xFFE76F51),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attendanceMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            height: 9,
            width: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF596579),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF141414),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentDrawer(BuildContext context, Map<String, dynamic> userData) {
    final name = userData["name"]?.toString().trim().isNotEmpty == true
        ? userData["name"].toString()
        : "Student";
    final classLabel = AcademicCatalog.classLabel(
      userData["class"]?.toString() ?? "",
    );

    return Drawer(
      backgroundColor: const Color(0xFFF7F8FB),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF171717),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Student Menu",
                    style: TextStyle(
                      color: Color(0xFFD6A241),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    classLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                children: [
                  _drawerSection(
                    context,
                    title: "Academics",
                    icon: Icons.school_rounded,
                    children: [
                      _drawerItem(
                        context,
                        "My Attendance",
                        Icons.check_circle_rounded,
                        "/student-attendance",
                        userData,
                      ),
                      _drawerItem(
                        context,
                        "Report Card",
                        Icons.assignment_rounded,
                        "/student-report-card",
                        userData,
                      ),
                      _drawerItem(
                        context,
                        "MCQ Tests",
                        Icons.quiz_rounded,
                        "/student-mcq-tests",
                        userData,
                      ),
                      _drawerItem(
                        context,
                        "Teacher's Remark",
                        Icons.rate_review_rounded,
                        "/student-teacher-remarks",
                        userData,
                      ),
                    ],
                  ),
                  _drawerSection(
                    context,
                    title: "Centre",
                    icon: Icons.apartment_rounded,
                    children: [
                      _drawerItem(
                        context,
                        "Updates",
                        Icons.campaign_rounded,
                        "/student-updates",
                        userData,
                      ),
                      _drawerItem(
                        context,
                        "Fees Status",
                        Icons.account_balance_wallet_rounded,
                        "/student-fees",
                        userData,
                      ),
                    ],
                  ),
                  _drawerSection(
                    context,
                    title: "Recognition",
                    icon: Icons.workspace_premium_rounded,
                    children: [
                      _drawerItem(
                        context,
                        "Stars of ME",
                        Icons.emoji_events_rounded,
                        "/student-stars",
                        userData,
                      ),
                      _drawerItem(
                        context,
                        "Current Stars",
                        Icons.auto_awesome_rounded,
                        "/student-current-stars",
                        userData,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          leading: Icon(icon, color: const Color(0xFF16786D)),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF141414),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context,
    String title,
    IconData icon,
    String route,
    Map<String, dynamic> userData,
  ) {
    return ListTile(
      dense: true,
      minLeadingWidth: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F3F8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF596579)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF2B3038),
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF9AA3B2),
        size: 20,
      ),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route, arguments: userData);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      drawer: _studentDrawer(context, userData),
      appBar: AppBar(
        title: const Text(
          "Student Dashboard",
          style: TextStyle(
            color: Color(0xFF141414),
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFF3F5F9),
        foregroundColor: const Color(0xFF141414),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            final insightsFuture = _loadDashboardInsights(
              userData,
              forceRefresh: true,
            );
            final mcqFuture = _loadLatestMcqResult(
              userData,
              forceRefresh: true,
            );
            setState(() {
              _dashboardInsightsFuture = insightsFuture;
              _latestMcqFuture = mcqFuture;
            });
            await Future.wait([insightsFuture, mcqFuture]);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              _premiumHeader(userData),
              const SizedBox(height: 14),
              _latestAnnouncementCard(context, userData),
              _latestMcqResultCard(context, userData),
              const SizedBox(height: 22),
              _analyticsSection(userData),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingRemark {
  _PendingRemark({
    required this.title,
    required this.preview,
    required this.date,
    required this.markRead,
  });

  final String title;
  final String preview;
  final DateTime date;
  final Future<void> Function() markRead;
}

class _LatestMcqResult {
  _LatestMcqResult({
    required this.title,
    required this.score,
    required this.correct,
    required this.wrong,
    required this.rank,
    required this.date,
    required this.testReference,
  });

  final String title;
  final String score;
  final String correct;
  final String wrong;
  final int rank;
  final DateTime date;
  final DocumentReference<Map<String, dynamic>>? testReference;

  _LatestMcqResult copyWith({int? rank}) {
    return _LatestMcqResult(
      title: title,
      score: score,
      correct: correct,
      wrong: wrong,
      rank: rank ?? this.rank,
      date: date,
      testReference: testReference,
    );
  }

  bool get isTopper => rank == 1;

  String get rankLabel {
    if (rank <= 0) return "Rank pending";
    if (isTopper) return "Rank #1 • Topper";
    return "Rank #$rank";
  }
}

class _DashboardInsights {
  _DashboardInsights({required this.comparisons, required this.attendance});

  factory _DashboardInsights.empty() {
    return _DashboardInsights(
      comparisons: const [],
      attendance: _AttendanceSummary.empty(),
    );
  }

  final List<_ScoreComparison> comparisons;
  final _AttendanceSummary attendance;
}

class _ScoreComparison {
  _ScoreComparison({
    required this.title,
    required this.subject,
    required this.date,
    required this.studentMarks,
    required this.averageMarks,
    required this.totalMarks,
  });

  final String title;
  final String subject;
  final DateTime date;
  final double studentMarks;
  final double averageMarks;
  final double totalMarks;

  double get studentPercent =>
      totalMarks <= 0 ? 0 : (studentMarks / totalMarks) * 100;

  double get averagePercent =>
      totalMarks <= 0 ? 0 : (averageMarks / totalMarks) * 100;

  String get studentScoreLabel =>
      "${_formatMcqScore(studentMarks)}/${_formatMcqScore(totalMarks)}";

  String get averageScoreLabel =>
      "${_formatMcqScore(averageMarks)}/${_formatMcqScore(totalMarks)}";

  String get shortLabel {
    final source = title.trim().isEmpty ? subject : title.trim();
    final words = source.split(RegExp(r"\s+")).where((word) => word.isNotEmpty);
    final label = words.take(2).join(" ");
    return label.isEmpty ? subject : label;
  }
}

class _AttendanceSummary {
  const _AttendanceSummary({
    required this.total,
    required this.present,
    required this.absent,
    required this.monthLabel,
  });

  factory _AttendanceSummary.empty() {
    return _AttendanceSummary(
      total: 0,
      present: 0,
      absent: 0,
      monthLabel: DateFormat("MMM yyyy").format(DateTime.now()),
    );
  }

  final int total;
  final int present;
  final int absent;
  final String monthLabel;

  String get percentLabel {
    if (total <= 0) return "0";
    return ((present / total) * 100).round().toString();
  }
}
