import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';
import 'mcq_result_utils.dart';

String _formatNumber(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

bool _looksLikeMobile(String value) {
  final compact = value.replaceAll(RegExp(r"[\s+\-()]"), "");
  return RegExp(r"^\d{8,}$").hasMatch(compact);
}

String _safeStudentName(String? value, {String fallback = "Student"}) {
  final name = value?.trim() ?? "";
  if (name.isEmpty || _looksLikeMobile(name)) return fallback;
  return name;
}

class StudentReportCardScreen extends StatefulWidget {
  const StudentReportCardScreen({super.key});

  @override
  State<StudentReportCardScreen> createState() =>
      _StudentReportCardScreenState();
}

class _StudentReportCardScreenState extends State<StudentReportCardScreen> {
  Future<_ReportData>? _reportFuture;
  String? _reportKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final userData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final key =
        "${userData["class"]?.toString() ?? ""}-${userData["mobile"]?.toString() ?? ""}";

    if (_reportKey == key && _reportFuture != null) return;

    _reportKey = key;
    _reportFuture = _loadReport(userData);
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

  String _feedbackOf(dynamic value) {
    if (value is! Map<String, dynamic>) return "";
    return value["feedback"]?.toString().trim() ?? "";
  }

  String _rankNameFor({
    required String? storedName,
    required String studentMobile,
    required String currentMobile,
    required String currentStudentName,
    required Map<String, String> studentDirectory,
  }) {
    final directoryName = studentDirectory[studentMobile]?.trim() ?? "";
    final fallback = studentMobile == currentMobile
        ? currentStudentName
        : _safeStudentName(directoryName);
    final name = storedName?.trim() ?? "";

    if (name.isEmpty ||
        _looksLikeMobile(name) ||
        (name.toLowerCase() == "student" && fallback != "Student")) {
      return fallback;
    }

    return name;
  }

  Future<_ReportData> _loadReport(Map<String, dynamic> userData) async {
    final className = userData["class"]?.toString() ?? "6";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final progressDocId = AcademicCatalog.batchDocId(className, batchName);
    final mobile = userData["mobile"]?.toString() ?? "";
    final currentStudentName = _safeStudentName(userData["name"]?.toString());
    final subjects = await AcademicCatalog.loadSubjectsForClass(className);
    final tests = <_ReportTest>[];
    final studentDirectorySnap = await FirebaseFirestore.instance
        .collection("users")
        .where("role", isEqualTo: "student")
        .where("class", isEqualTo: className)
        .get();
    final studentDirectory = <String, String>{
      for (final doc in studentDirectorySnap.docs)
        if (AcademicCatalog.batchMatches(doc.data(), batchName))
          doc.id: _safeStudentName(doc.data()["name"]?.toString()),
    };
    studentDirectory[mobile] = _rankNameFor(
      storedName: studentDirectory[mobile],
      studentMobile: mobile,
      currentMobile: mobile,
      currentStudentName: currentStudentName,
      studentDirectory: studentDirectory,
    );
    final progressFutures = subjects.map((subject) {
      return FirebaseFirestore.instance
          .collection("progress")
          .doc(progressDocId)
          .collection(subject)
          .get();
    }).toList();
    final mcqFuture = FirebaseFirestore.instance
        .collection("mcq_tests")
        .where("status", isEqualTo: "released")
        .orderBy("scheduledAt", descending: true)
        .limit(QueryLimits.studentMcqTests)
        .get();

    final progressSnaps = await Future.wait(progressFutures);

    for (var subjectIndex = 0; subjectIndex < subjects.length; subjectIndex++) {
      final subject = subjects[subjectIndex];
      final snap = progressSnaps[subjectIndex];
      for (final doc in snap.docs) {
        final data = doc.data();
        final studentsRaw = data["students"];
        final studentMap = studentsRaw is Map<String, dynamic>
            ? Map<String, dynamic>.from(studentsRaw)
            : <String, dynamic>{};

        studentMap.putIfAbsent(
          mobile,
          () => {
            "marks": "",
            "absent": true,
            "feedback": "",
            "type": "",
            "feedbackRead": true,
          },
        );

        final appearedEntries = studentMap.entries
            .where((entry) => !_isAbsent(entry.value))
            .toList();

        final ranking =
            appearedEntries.map((entry) {
              final value = entry.value;
              final name = value is Map<String, dynamic>
                  ? value["name"]?.toString().trim()
                  : null;
              return _RankEntry(
                mobile: entry.key,
                name: _rankNameFor(
                  storedName: name,
                  studentMobile: entry.key,
                  currentMobile: mobile,
                  currentStudentName: currentStudentName,
                  studentDirectory: studentDirectory,
                ),
                marks: _marksOf(entry.value),
              );
            }).toList()..sort((a, b) {
              final marksCompare = b.marks.compareTo(a.marks);
              if (marksCompare != 0) return marksCompare;
              return a.name.compareTo(b.name);
            });

        final ownMarks = _marksOf(studentMap[mobile]);
        final isAbsent = _isAbsent(studentMap[mobile]);
        final totalMarks =
            double.tryParse(data["totalMarks"]?.toString() ?? "0") ?? 0;
        final average = ranking.isEmpty
            ? 0.0
            : ranking.fold<double>(0, (total, e) => total + e.marks) /
                  ranking.length;
        final topper = ranking.isEmpty ? 0.0 : ranking.first.marks;
        final rank = isAbsent
            ? 0
            : ranking.indexWhere((entry) => entry.mobile == mobile) + 1;

        tests.add(
          _ReportTest(
            subject: subject,
            topic: data["chapter"]?.toString().trim().isEmpty == false
                ? data["chapter"].toString()
                : "Test",
            date: _testDate(data["date"], doc.id),
            totalMarks: totalMarks,
            ownMarks: ownMarks,
            isAbsent: isAbsent,
            average: average,
            topperMarks: topper,
            rank: rank,
            ranking: ranking,
            currentMobile: mobile,
            feedback: _feedbackOf(studentMap[mobile]),
          ),
        );
      }
    }

    final mcqSnap = await mcqFuture;
    final classMcqDocs = mcqSnap.docs
        .where((doc) => AcademicCatalog.mcqTargetClass(doc.data()) == className)
        .toList();
    final ownResultPairs = await Future.wait(
      classMcqDocs.map((doc) async {
        final resultDoc = await doc.reference
            .collection("results")
            .doc(mobile)
            .get();
        return (testDoc: doc, resultDoc: resultDoc);
      }),
    );
    final appearedMcqs = ownResultPairs
        .where((pair) => pair.resultDoc.exists)
        .toList();
    final rankingSnaps = await Future.wait(
      appearedMcqs.map(
        (pair) => pair.testDoc.reference
            .collection("results")
            .orderBy("score", descending: true)
            .orderBy("timeTakenSeconds")
            .orderBy("submittedAt")
            .limit(QueryLimits.mcqPreviewResults)
            .get(),
      ),
    );

    for (var i = 0; i < appearedMcqs.length; i++) {
      final testDoc = appearedMcqs[i].testDoc;
      final ownResult = appearedMcqs[i].resultDoc.data() ?? {};
      final data = testDoc.data();
      final resultsSnap = rankingSnaps[i];
      final resultDocs = resultsSnap.docs;
      final computedOwnResult = computeMcqResult(data, ownResult);

      final ranking =
          resultDocs.map((resultDoc) {
            final result = computeMcqResult(data, resultDoc.data());
            final resultMobile = result.mobile.isEmpty
                ? resultDoc.id
                : result.mobile;
            return _RankEntry(
              mobile: resultMobile,
              name: _rankNameFor(
                storedName: result.studentName,
                studentMobile: resultMobile,
                currentMobile: mobile,
                currentStudentName: currentStudentName,
                studentDirectory: studentDirectory,
              ),
              marks: result.score,
              timeTakenSeconds: result.timeTakenSeconds,
            );
          }).toList()..sort((a, b) {
            final marksCompare = b.marks.compareTo(a.marks);
            if (marksCompare != 0) return marksCompare;
            return a.timeTakenSeconds.compareTo(b.timeTakenSeconds);
          });

      final ownMarks = computedOwnResult.score;
      final totalMarks = computedOwnResult.totalMarks;
      final average = ranking.isEmpty
          ? 0.0
          : ranking.fold<double>(0, (total, e) => total + e.marks) /
                ranking.length;
      final topper = ranking.isEmpty ? 0.0 : ranking.first.marks;
      final rank = ranking.indexWhere((entry) => entry.mobile == mobile) + 1;

      tests.add(
        _ReportTest(
          subject: "MCQ Test",
          topic: data["chapterName"]?.toString().trim().isEmpty == false
              ? data["chapterName"].toString()
              : "MCQ Test",
          date: _testDate(data["scheduledAt"], testDoc.id),
          totalMarks: totalMarks,
          ownMarks: ownMarks,
          isAbsent: false,
          average: average,
          topperMarks: topper,
          rank: rank,
          ranking: ranking,
          currentMobile: mobile,
          feedback:
              "${computedOwnResult.correctCount} correct • ${computedOwnResult.wrongCount} wrong",
        ),
      );
    }

    tests.sort((a, b) => b.date.compareTo(a.date));
    return _ReportData(tests: tests);
  }

  @override
  Widget build(BuildContext context) {
    final reportFuture = _reportFuture;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Report Card"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Tests"),
              Tab(text: "Analysis"),
              Tab(text: "Ranks"),
            ],
          ),
        ),
        body: FutureBuilder<_ReportData>(
          future: reportFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Could not fetch report card. Please try again after the latest records sync.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final tests = snapshot.data!.tests;
            if (tests.isEmpty) {
              return const Center(child: Text("No report card available yet"));
            }

            return TabBarView(
              children: [
                _TestsTab(tests: tests),
                _AnalysisTab(tests: tests),
                _RanksTab(tests: tests),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TestsTab extends StatelessWidget {
  const _TestsTab({required this.tests});

  final List<_ReportTest> tests;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tests.length,
      itemBuilder: (context, index) {
        final test = tests[index];
        final accent = test.isAbsent
            ? const Color(0xFFDC2626)
            : _accentColor(index);
        final scorePercent = test.totalMarks <= 0 || test.isAbsent
            ? 0.0
            : (test.ownMarks / test.totalMarks).clamp(0.0, 1.0);
        final rankLabel = test.isAbsent
            ? "Absent"
            : test.rank <= 0
            ? "Rank pending"
            : "Rank #${test.rank}";
        final percentLabel = test.isAbsent
            ? "Ab"
            : test.totalMarks <= 0
            ? "--"
            : "${(scorePercent * 100).round()}%";

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 58,
                width: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  percentLabel,
                  style: TextStyle(
                    color: accent,
                    fontSize: 17,
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
                      test.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TestPill(
                          icon: Icons.menu_book_rounded,
                          label: test.subject,
                          color: accent,
                        ),
                        _TestPill(
                          icon: Icons.workspace_premium_rounded,
                          label: rankLabel,
                          color: accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: scorePercent,
                        minHeight: 8,
                        backgroundColor: accent.withValues(alpha: 0.10),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    test.isAbsent
                        ? "Absent"
                        : "${_formatNumber(test.ownMarks)}/${_formatNumber(test.totalMarks)}",
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DateFormat("dd MMM").format(test.date),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _accentColor(int index) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF0F766E),
      Color(0xFFDB2777),
      Color(0xFFEA580C),
    ];
    return colors[index % colors.length];
  }
}

class _TestPill extends StatelessWidget {
  const _TestPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTab extends StatelessWidget {
  const _AnalysisTab({required this.tests});

  final List<_ReportTest> tests;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tests.length,
      itemBuilder: (context, index) {
        final test = tests[index];
        final maxValue = [
          test.totalMarks,
          test.ownMarks,
          test.average,
          test.topperMarks,
        ].reduce((a, b) => a > b ? a : b);
        final scoreText = test.isAbsent
            ? "Absent"
            : "${_formatNumber(test.ownMarks)}/${test.totalMarks == 0 ? "-" : _formatNumber(test.totalMarks)}";

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              leading: Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF6D5DF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.analytics, color: Color(0xFF6D5DF6)),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      test.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: test.isAbsent
                          ? Colors.red.shade50
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      scoreText,
                      style: TextStyle(
                        color: test.isAbsent
                            ? Colors.red.shade700
                            : Colors.green.shade800,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  "${test.subject} • ${DateFormat("dd MMM yyyy").format(test.date)}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              children: [
                if (test.isAbsent)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      "Absent from this test. Class comparison is shown below.",
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                _VerticalScoreChart(
                  maxValue: maxValue <= 0 ? 1 : maxValue,
                  items: [
                    _ScoreBarData(
                      label: "You",
                      value: test.isAbsent ? 0 : test.ownMarks,
                      color: test.isAbsent ? Colors.red : Colors.indigo,
                      caption: test.isAbsent
                          ? "Ab"
                          : _formatNumber(test.ownMarks),
                    ),
                    _ScoreBarData(
                      label: "Average",
                      value: test.average,
                      color: Colors.teal,
                      caption: _formatNumber(test.average),
                    ),
                    _ScoreBarData(
                      label: "Topper",
                      value: test.topperMarks,
                      color: Colors.orange,
                      caption: _formatNumber(test.topperMarks),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _analysisChip(
                        "Maximum",
                        test.totalMarks == 0
                            ? "-"
                            : _formatNumber(test.totalMarks),
                        Icons.flag,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _analysisChip(
                        "Rank",
                        test.isAbsent ? "-" : "#${test.rank}",
                        Icons.leaderboard,
                        Colors.purple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _analysisChip(
    String label,
    String value,
    IconData icon,
    MaterialColor color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color.shade900,
                    fontSize: 15,
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
}

class _VerticalScoreChart extends StatelessWidget {
  const _VerticalScoreChart({required this.items, required this.maxValue});

  final List<_ScoreBarData> items;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: items.map((item) {
          final ratio = (item.value / maxValue).clamp(0.0, 1.0);
          final barHeight = 112 * ratio;

          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  item.caption,
                  style: TextStyle(
                    color: item.color.shade800,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    height: barHeight < 6 && item.value > 0 ? 6 : barHeight,
                    width: 34,
                    decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: item.color.withValues(alpha: 0.24),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ScoreBarData {
  _ScoreBarData({
    required this.label,
    required this.value,
    required this.color,
    required this.caption,
  });

  final String label;
  final double value;
  final MaterialColor color;
  final String caption;
}

class _RanksTab extends StatelessWidget {
  const _RanksTab({required this.tests});

  final List<_ReportTest> tests;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tests.length,
      itemBuilder: (context, index) {
        final test = tests[index];
        final accent = test.isAbsent
            ? const Color(0xFFDC2626)
            : _accentColor(index);
        final appeared = test.ranking.length;
        final rankLabel = test.isAbsent
            ? "Absent"
            : test.rank <= 0
            ? "Rank pending"
            : "Rank #${test.rank}";

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              leading: Container(
                height: 44,
                width: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.leaderboard_rounded, color: accent),
              ),
              title: Text(
                test.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TestPill(
                      icon: Icons.menu_book_rounded,
                      label: test.subject,
                      color: accent,
                    ),
                    _TestPill(
                      icon: Icons.workspace_premium_rounded,
                      label: rankLabel,
                      color: accent,
                    ),
                    _TestPill(
                      icon: Icons.groups_rounded,
                      label: "$appeared appeared",
                      color: const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
              children: [
                if (test.ranking.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      "No student appeared in this test yet.",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  )
                else
                  ...test.ranking.asMap().entries.map((entry) {
                    final rankIndex = entry.key;
                    final rank = entry.value;
                    final isTopper = rankIndex == 0;
                    final isCurrentStudent = rank.mobile == test.currentMobile;
                    final canShow = rankIndex < 3 || isCurrentStudent;

                    return Container(
                      margin: EdgeInsets.only(bottom: isTopper ? 10 : 8),
                      padding: EdgeInsets.all(isTopper ? 13 : 10),
                      decoration: BoxDecoration(
                        color: isTopper
                            ? const Color(0xFFFFFBEB)
                            : isCurrentStudent
                            ? Colors.amber.shade100
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(isTopper ? 16 : 12),
                        border: Border.all(
                          color: isTopper
                              ? const Color(0xFFF59E0B)
                              : isCurrentStudent
                              ? Colors.amber.shade300
                              : Colors.transparent,
                          width: isTopper ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: isTopper ? 17 : 14,
                            backgroundColor: isTopper
                                ? const Color(0xFFF59E0B)
                                : Colors.white,
                            child: isTopper
                                ? const Icon(
                                    Icons.emoji_events,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : Text(
                                    "#${rankIndex + 1}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  canShow ? rank.name : "Hidden student",
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: isTopper ? 16 : 14,
                                    fontWeight: isTopper || isCurrentStudent
                                        ? FontWeight.w900
                                        : FontWeight.w500,
                                    color: canShow
                                        ? isTopper
                                              ? const Color(0xFF92400E)
                                              : Colors.black
                                        : Colors.grey,
                                  ),
                                ),
                                if (isTopper && canShow)
                                  Text(
                                    isCurrentStudent
                                        ? "You are the topper"
                                        : "Topper",
                                    style: const TextStyle(
                                      color: Color(0xFFB45309),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (canShow)
                            Text(
                              _formatNumber(rank.marks),
                              style: TextStyle(
                                color: isTopper
                                    ? const Color(0xFF92400E)
                                    : Colors.black,
                                fontSize: isTopper ? 16 : 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _accentColor(int index) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF0F766E),
      Color(0xFFDB2777),
      Color(0xFFEA580C),
    ];
    return colors[index % colors.length];
  }
}

class _ReportData {
  _ReportData({required this.tests});

  final List<_ReportTest> tests;
}

class _ReportTest {
  _ReportTest({
    required this.subject,
    required this.topic,
    required this.date,
    required this.totalMarks,
    required this.ownMarks,
    required this.isAbsent,
    required this.average,
    required this.topperMarks,
    required this.rank,
    required this.ranking,
    required this.currentMobile,
    required this.feedback,
  });

  final String subject;
  final String topic;
  final DateTime date;
  final double totalMarks;
  final double ownMarks;
  final bool isAbsent;
  final double average;
  final double topperMarks;
  final int rank;
  final List<_RankEntry> ranking;
  final String currentMobile;
  final String feedback;
}

class _RankEntry {
  _RankEntry({
    required this.mobile,
    required this.name,
    required this.marks,
    this.timeTakenSeconds = 0,
  });

  final String mobile;
  final String name;
  final double marks;
  final int timeTakenSeconds;
}
