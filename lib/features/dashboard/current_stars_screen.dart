import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/academic_catalog.dart';
import 'mcq_result_utils.dart';

class CurrentStarsScreen extends StatefulWidget {
  const CurrentStarsScreen({super.key});

  @override
  State<CurrentStarsScreen> createState() => _CurrentStarsScreenState();
}

class _CurrentStarsScreenState extends State<CurrentStarsScreen> {
  late Future<List<_ClassTopperGroup>> _starsFuture;

  @override
  void initState() {
    super.initState();
    _starsFuture = _loadReportCardStars();
  }

  static const _classOrder = ["5", "6", "7", "8", "9", "10"];

  Future<List<_ClassTopperGroup>> _loadReportCardStars() async {
    final groups = await Future.wait(
      _classOrder.map((className) async {
        final studentsSnap = await FirebaseFirestore.instance
            .collection("users")
            .where("role", isEqualTo: "student")
            .where("class", isEqualTo: className)
            .get();
        final studentDirectory = <String, String>{
          for (final doc in studentsSnap.docs)
            doc.id: _safeStudentName(doc.data()["name"]?.toString()),
        };
        final entriesByMobile = <String, _ReportCardStarEntry>{};
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

        for (
          var queryIndex = 0;
          queryIndex < progressQueries.length;
          queryIndex++
        ) {
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
                      if (_isAbsent(value)) return null;
                      final marks = _marksOf(value);
                      return (
                        mobile: entry.key,
                        name: _studentNameFromValue(
                          value,
                          entry.key,
                          studentDirectory,
                        ),
                        percentage: (marks / totalMarks) * 100,
                        marks: marks,
                      );
                    })
                    .whereType<
                      ({
                        String mobile,
                        String name,
                        double percentage,
                        double marks,
                      })
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
            final testDate = _testDate(data["date"], doc.id);
            final chapter = data["chapter"]?.toString().trim();
            final testName =
                "${chapter?.isNotEmpty == true ? chapter : "Test"} • $subject"
                "${batch == AcademicCatalog.homeTuitionBatch ? " • Home Tuition" : ""}";

            for (final topper in appeared.where(
              (entry) => (entry.percentage - topPercentage).abs() < 0.0001,
            )) {
              _addTopper(
                entriesByMobile,
                className: className,
                mobile: topper.mobile,
                name: topper.name,
                percentage: topper.percentage,
                testDate: testDate,
                testName: testName,
              );
            }
          }
        }

        final mcqSnap = await FirebaseFirestore.instance
            .collection("mcq_tests")
            .where("status", isEqualTo: "released")
            .get();
        final classMcqDocs = mcqSnap.docs
            .where(
              (testDoc) =>
                  AcademicCatalog.mcqTargetClass(testDoc.data()) == className,
            )
            .toList();

        await Future.wait(
          classMcqDocs.map((testDoc) async {
            final testData = testDoc.data();
            final resultsSnap = await testDoc.reference
                .collection("results")
                .get();
            final results =
                resultsSnap.docs
                    .map((doc) {
                      final result = computeMcqResult(testData, doc.data());
                      final mobile = result.mobile.isEmpty
                          ? doc.id
                          : result.mobile;
                      return (
                        mobile: mobile,
                        name: _safeStudentName(
                          result.studentName,
                          fallback: studentDirectory[mobile] ?? "Student",
                        ),
                        percentage: result.percentage,
                        marks: result.score,
                        result: result,
                      );
                    })
                    .where((entry) => entry.result.totalMarks > 0)
                    .toList()
                  ..sort((a, b) {
                    final percentCompare = b.percentage.compareTo(a.percentage);
                    if (percentCompare != 0) return percentCompare;
                    final marksCompare = b.marks.compareTo(a.marks);
                    if (marksCompare != 0) return marksCompare;
                    final timeCompare = a.result.timeTakenSeconds.compareTo(
                      b.result.timeTakenSeconds,
                    );
                    if (timeCompare != 0) return timeCompare;
                    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                  });

            if (results.isEmpty) return;
            final topPercentage = results.first.percentage;
            final testDate = mcqScheduledAt(testData);
            final chapter = testData["chapterName"]?.toString().trim();
            final testName = chapter?.isNotEmpty == true
                ? chapter!
                : "MCQ Test";

            for (final topper in results.where(
              (entry) => (entry.percentage - topPercentage).abs() < 0.0001,
            )) {
              _addTopper(
                entriesByMobile,
                className: className,
                mobile: topper.mobile,
                name: topper.name,
                percentage: topper.percentage,
                testDate: testDate,
                testName: testName,
              );
            }
          }),
        );

        final entries = entriesByMobile.values.toList()
          ..sort(_compareReportCardStars);
        return _ClassTopperGroup(className: className, stars: entries);
      }),
    );

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("Wall Of Fame"),
        backgroundColor: const Color(0xFFF5F7FB),
      ),
      body: FutureBuilder<List<_ClassTopperGroup>>(
        future: _starsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _CurrentStarsError(error: snapshot.error);
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final groups = snapshot.data!;
          final totalStars = groups.fold<int>(
            0,
            (total, group) => total + group.stars.length,
          );
          if (totalStars == 0) {
            return const Center(child: Text("No report-card toppers yet"));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _CurrentStarsHero(totalStudents: totalStars),
              const SizedBox(height: 14),
              ...groups.map((group) {
                final style = _ClassSectionStyle.forClass(group.className);
                return _ClassStarsSection(group: group, style: style);
              }),
            ],
          );
        },
      ),
    );
  }
}

class _CurrentStarsHero extends StatelessWidget {
  const _CurrentStarsHero({required this.totalStudents});

  final int totalStudents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF101820), Color(0xFF244C5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC857).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFFC857).withValues(alpha: 0.34),
              ),
            ),
            child: const Icon(Icons.auto_awesome, color: Color(0xFFFFC857)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Current Stars",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$totalStudents students topped report-card tests so far",
                  style: const TextStyle(
                    color: Color(0xFFB7C6CE),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _ClassStarsSection extends StatelessWidget {
  const _ClassStarsSection({required this.group, required this.style});

  final _ClassTopperGroup group;
  final _ClassSectionStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: style.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: style.accent.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: style.accent.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: style.accent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.school,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AcademicCatalog.classLabel(group.className),
                      style: TextStyle(
                        color: style.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    "${group.stars.length} stars",
                    style: TextStyle(
                      color: style.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (group.stars.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 6, 14, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "No toppers recorded for this class yet",
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: Row(
                  children: [
                    _HeaderCell(label: "Rank", flex: 2),
                    _HeaderCell(label: "Student", flex: 5),
                    _HeaderCell(label: "%", flex: 2, alignEnd: true),
                    _HeaderCell(label: "Tops", flex: 2, alignEnd: true),
                  ],
                ),
              ),
              Divider(height: 1, color: style.accent.withValues(alpha: 0.12)),
              ...group.stars.asMap().entries.map((entry) {
                return _CurrentStarTableRow(
                  rank: entry.key + 1,
                  star: entry.value,
                  style: style,
                );
              }),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.flex,
    this.alignEnd = false,
  });

  final String label;
  final int flex;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CurrentStarTableRow extends StatelessWidget {
  const _CurrentStarTableRow({
    required this.rank,
    required this.star,
    required this.style,
  });

  final int rank;
  final _ReportCardStarEntry star;
  final _ClassSectionStyle style;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat("dd MMM yyyy").format(star.latestTopAt);
    final rankColor = rank == 1
        ? const Color(0xFFD97706)
        : rank == 2
        ? const Color(0xFF64748B)
        : rank == 3
        ? const Color(0xFFB45309)
        : style.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: rank <= 3 ? rankColor.withValues(alpha: 0.06) : Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.045)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 32,
                width: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "#$rank",
                  style: TextStyle(
                    color: rankColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  star.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Latest: $date • ${star.latestTestName}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              "${_formatNumber(star.averageTopPercentage)}%",
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  "${star.toppedCount}x",
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassTopperGroup {
  const _ClassTopperGroup({required this.className, required this.stars});

  final String className;
  final List<_ReportCardStarEntry> stars;
}

class _ReportCardStarEntry {
  const _ReportCardStarEntry({
    required this.mobile,
    required this.name,
    required this.className,
    required this.toppedCount,
    required this.totalTopPercentage,
    required this.bestTopPercentage,
    required this.latestTopAt,
    required this.latestTestName,
  });

  final String mobile;
  final String name;
  final String className;
  final int toppedCount;
  final double totalTopPercentage;
  final double bestTopPercentage;
  final DateTime latestTopAt;
  final String latestTestName;

  double get averageTopPercentage =>
      toppedCount <= 0 ? 0 : totalTopPercentage / toppedCount;

  _ReportCardStarEntry copyWith({
    int? toppedCount,
    double? totalTopPercentage,
    double? bestTopPercentage,
    DateTime? latestTopAt,
    String? latestTestName,
  }) {
    return _ReportCardStarEntry(
      mobile: mobile,
      name: name,
      className: className,
      toppedCount: toppedCount ?? this.toppedCount,
      totalTopPercentage: totalTopPercentage ?? this.totalTopPercentage,
      bestTopPercentage: bestTopPercentage ?? this.bestTopPercentage,
      latestTopAt: latestTopAt ?? this.latestTopAt,
      latestTestName: latestTestName ?? this.latestTestName,
    );
  }
}

class _ClassSectionStyle {
  const _ClassSectionStyle({
    required this.accent,
    required this.surface,
    required this.text,
  });

  final Color accent;
  final Color surface;
  final Color text;

  static _ClassSectionStyle forClass(String className) {
    switch (className) {
      case "6":
        return const _ClassSectionStyle(
          accent: Color(0xFF2563EB),
          surface: Color(0xFFF8FBFF),
          text: Color(0xFF1E3A8A),
        );
      case "7":
        return const _ClassSectionStyle(
          accent: Color(0xFF0F766E),
          surface: Color(0xFFF2FFFC),
          text: Color(0xFF134E4A),
        );
      case "8":
        return const _ClassSectionStyle(
          accent: Color(0xFF7C3AED),
          surface: Color(0xFFFBF7FF),
          text: Color(0xFF4C1D95),
        );
      case "9":
        return const _ClassSectionStyle(
          accent: Color(0xFFDB2777),
          surface: Color(0xFFFFF7FB),
          text: Color(0xFF831843),
        );
      default:
        return const _ClassSectionStyle(
          accent: Color(0xFFEA580C),
          surface: Color(0xFFFFFAF4),
          text: Color(0xFF7C2D12),
        );
    }
  }
}

class _CurrentStarsError extends StatelessWidget {
  const _CurrentStarsError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFDC2626),
                size: 34,
              ),
              const SizedBox(height: 10),
              const Text(
                "Current toppers could not load",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF991B1B),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                error?.toString() ?? "Please try again.",
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatNumber(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

void _addTopper(
  Map<String, _ReportCardStarEntry> entriesByMobile, {
  required String className,
  required String mobile,
  required String name,
  required double percentage,
  required DateTime testDate,
  required String testName,
}) {
  final existing = entriesByMobile[mobile];
  if (existing == null) {
    entriesByMobile[mobile] = _ReportCardStarEntry(
      mobile: mobile,
      name: name,
      className: className,
      toppedCount: 1,
      totalTopPercentage: percentage,
      bestTopPercentage: percentage,
      latestTopAt: testDate,
      latestTestName: testName,
    );
    return;
  }

  final isLatest = testDate.isAfter(existing.latestTopAt);
  entriesByMobile[mobile] = existing.copyWith(
    toppedCount: existing.toppedCount + 1,
    totalTopPercentage: existing.totalTopPercentage + percentage,
    bestTopPercentage: percentage > existing.bestTopPercentage
        ? percentage
        : existing.bestTopPercentage,
    latestTopAt: isLatest ? testDate : existing.latestTopAt,
    latestTestName: isLatest ? testName : existing.latestTestName,
  );
}

int _compareReportCardStars(_ReportCardStarEntry a, _ReportCardStarEntry b) {
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

bool _isAbsent(dynamic value) {
  if (value is! Map) return true;
  return value["absent"] == true ||
      value["marks"]?.toString().trim().toLowerCase() == "ab";
}

double _marksOf(dynamic value) {
  if (value is! Map) return 0;
  return double.tryParse(value["marks"]?.toString() ?? "") ?? 0;
}

String _studentNameFromValue(
  dynamic value,
  String mobile,
  Map<String, String> studentDirectory,
) {
  final storedName = value is Map ? value["name"]?.toString() : null;
  return _safeStudentName(
    storedName,
    fallback: studentDirectory[mobile] ?? "Student",
  );
}

String _safeStudentName(String? value, {String fallback = "Student"}) {
  final name = value?.trim() ?? "";
  if (name.isEmpty || _looksLikeMobile(name)) return fallback;
  return name;
}

bool _looksLikeMobile(String value) {
  final compact = value.replaceAll(RegExp(r"[\s+\-()]"), "");
  return RegExp(r"^\d{8,}$").hasMatch(compact);
}
