import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';

class StudentTeacherRemarksScreen extends StatelessWidget {
  const StudentTeacherRemarksScreen({super.key});

  DateTime _dateFrom(dynamic value, String fallbackId) {
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

  Future<List<_RemarkItem>> _loadRemarks(Map<String, dynamic> userData) async {
    final mobile = userData["mobile"]?.toString() ?? "";
    final className = userData["class"]?.toString() ?? "6";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final progressDocId = AcademicCatalog.batchDocId(className, batchName);
    final remarks = <_RemarkItem>[];

    final generalSnap = await FirebaseFirestore.instance
        .collection("teacher_remarks")
        .where("mobile", isEqualTo: mobile)
        .get();

    for (final doc in generalSnap.docs) {
      final data = doc.data();
      if (!AcademicCatalog.batchMatches(data, batchName)) continue;
      final text = data["remark"]?.toString().trim() ?? "";
      final homeworkEnabled = data["homeworkEnabled"] == true;
      final classPerformanceEnabled = data["classPerformanceEnabled"] == true;
      final homeworkRating = int.tryParse(
        data["homeworkRating"]?.toString() ?? "",
      );
      final classPerformanceRating = int.tryParse(
        data["classPerformanceRating"]?.toString() ?? "",
      );

      if (text.isEmpty && !homeworkEnabled && !classPerformanceEnabled) {
        continue;
      }

      remarks.add(
        _RemarkItem(
          title: "General Remark",
          subtitle: "Teacher note",
          text: text,
          date: _dateFrom(data["createdAt"], doc.id),
          type: _RemarkType.general,
          homeworkRating: homeworkEnabled ? homeworkRating : null,
          classPerformanceRating: classPerformanceEnabled
              ? classPerformanceRating
              : null,
        ),
      );
    }

    for (final subject in await AcademicCatalog.loadSubjectsForClass(
      className,
    )) {
      final testsSnap = await FirebaseFirestore.instance
          .collection("progress")
          .doc(progressDocId)
          .collection(subject)
          .get();

      for (final doc in testsSnap.docs) {
        final data = doc.data();
        final studentsRaw = data["students"];
        if (studentsRaw is! Map<String, dynamic>) continue;

        final studentData = studentsRaw[mobile];
        if (studentData is! Map<String, dynamic>) continue;

        final feedback = studentData["feedback"]?.toString().trim() ?? "";
        if (feedback.isEmpty) continue;

        remarks.add(
          _RemarkItem(
            title: data["chapter"]?.toString().trim().isEmpty == false
                ? data["chapter"].toString()
                : "Test Remark",
            subtitle: "$subject • Test Remark",
            text: feedback,
            date: _dateFrom(data["date"], doc.id),
            type: _RemarkType.test,
          ),
        );
      }
    }

    remarks.sort((a, b) => b.date.compareTo(a.date));
    return remarks;
  }

  @override
  Widget build(BuildContext context) {
    final userData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FB),
      appBar: AppBar(title: const Text("Teacher's Remark"), centerTitle: true),
      body: FutureBuilder<List<_RemarkItem>>(
        future: _loadRemarks(userData),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final remarks = snapshot.data!;

          if (remarks.isEmpty) {
            return const Center(child: Text("No teacher remarks yet"));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: remarks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = remarks[index];
              final accent = item.type == _RemarkType.test
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF0F766E);
              final hasRatings =
                  item.homeworkRating != null ||
                  item.classPerformanceRating != null;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: 0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.type == _RemarkType.test
                                ? "Test remark"
                                : "General remark",
                            style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat("dd MMM yyyy").format(item.date),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasRatings) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (item.homeworkRating != null)
                            Expanded(
                              child: _ratingCard(
                                "Homework",
                                item.homeworkRating!,
                                Icons.home_work_outlined,
                                Colors.indigo,
                              ),
                            ),
                          if (item.homeworkRating != null &&
                              item.classPerformanceRating != null)
                            const SizedBox(width: 10),
                          if (item.classPerformanceRating != null)
                            Expanded(
                              child: _ratingCard(
                                "Performance",
                                item.classPerformanceRating!,
                                Icons.trending_up,
                                Colors.teal,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (item.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          item.text,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _ratingCard(
    String label,
    int value,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color.shade700, size: 18),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(5, (index) {
              return Icon(
                index < value ? Icons.star_rounded : Icons.star_border_rounded,
                color: color.shade600,
                size: 17,
              );
            }),
          ),
          const SizedBox(height: 3),
          Text(
            "$value/5",
            style: TextStyle(
              color: color.shade900,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

enum _RemarkType { test, general }

class _RemarkItem {
  _RemarkItem({
    required this.title,
    required this.subtitle,
    required this.text,
    required this.date,
    required this.type,
    this.homeworkRating,
    this.classPerformanceRating,
  });

  final String title;
  final String subtitle;
  final String text;
  final DateTime date;
  final _RemarkType type;
  final int? homeworkRating;
  final int? classPerformanceRating;
}
