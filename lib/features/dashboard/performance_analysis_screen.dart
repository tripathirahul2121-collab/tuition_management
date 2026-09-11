import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';
import 'mcq_result_utils.dart';

const String _mcqSubject = "MCQ Tests";

class PerformanceAnalysisScreen extends StatefulWidget {
  const PerformanceAnalysisScreen({super.key});

  @override
  State<PerformanceAnalysisScreen> createState() =>
      _PerformanceAnalysisScreenState();
}

class _PerformanceAnalysisScreenState extends State<PerformanceAnalysisScreen> {
  String selectedClass = "6";
  String selectedBatch = AcademicCatalog.regularBatch;
  String selectedSubject = "Maths";

  int? expandedIndex; // 🔥 controls expand/collapse
  final TextInputFormatter decimalMarksFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
        final text = newValue.text;
        final isValid =
            text.isEmpty || RegExp(r'^\d{0,3}(\.\d{0,2})?$').hasMatch(text);
        return isValid ? newValue : oldValue;
      });

  Stream<DocumentSnapshot<Map<String, dynamic>>> _customSubjectsStream() {
    return AcademicCatalog.customSubjectsStream(selectedClass);
  }

  List<String> _subjectsWithCustom(Map<String, dynamic>? data) {
    return AcademicCatalog.subjectsWithCustom(selectedClass, data);
  }

  Stream<QuerySnapshot> _testsStream() {
    return FirebaseFirestore.instance
        .collection("progress")
        .doc(AcademicCatalog.batchDocId(selectedClass, selectedBatch))
        .collection(selectedSubject)
        .orderBy("date", descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> _mcqTestsStream() {
    return FirebaseFirestore.instance
        .collection("mcq_tests")
        .where("status", isEqualTo: "released")
        .orderBy("scheduledAt", descending: true)
        .limit(QueryLimits.mcqTests)
        .snapshots();
  }

  Stream<QuerySnapshot> _studentsStream() {
    return FirebaseFirestore.instance
        .collection("users")
        .where("role", isEqualTo: "student")
        .where("class", isEqualTo: selectedClass)
        .orderBy("name")
        .snapshots();
  }

  String formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "";
    return DateFormat("dd MMM yyyy").format(timestamp.toDate());
  }

  bool _isAbsent(dynamic value) {
    if (value is! Map<String, dynamic>) return false;
    return value["absent"] == true ||
        value["marks"]?.toString().trim().toLowerCase() == "ab";
  }

  Future<void> _deleteTest(DocumentReference reference, String title) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete test?"),
        content: Text(
          title.isEmpty
              ? "This test record will be removed permanently."
              : "\"$title\" will be removed permanently.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;
    await reference.delete();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Test deleted")));
  }

  Future<void> _editStudentRecord({
    required DocumentReference reference,
    required String mobile,
    required String name,
    required Map<String, dynamic> current,
  }) async {
    final marksController = TextEditingController(
      text: current["marks"]?.toString() ?? "",
    );
    final feedbackController = TextEditingController(
      text: current["feedback"]?.toString() ?? "",
    );
    bool isAbsent = current["absent"] == true;

    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Update $name",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: marksController,
                          enabled: !isAbsent,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [decimalMarksFormatter],
                          decoration: const InputDecoration(
                            labelText: "Marks",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Absent"),
                          value: isAbsent,
                          onChanged: (value) {
                            setSheetState(() {
                              isAbsent = value;
                              if (value) marksController.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: feedbackController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: "Teacher's Remark",
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(Icons.save),
                            label: const Text("Update Record"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldSave != true) return;

    await reference.update({
      "students.$mobile.marks": isAbsent ? "" : marksController.text.trim(),
      "students.$mobile.absent": isAbsent,
      "students.$mobile.feedback": feedbackController.text.trim(),
      "students.$mobile.type": feedbackController.text.trim().isEmpty
          ? ""
          : (current["type"]?.toString() ?? "Positive"),
      "students.$mobile.feedbackRead": feedbackController.text.trim().isEmpty,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$name updated")));
  }

  Map<String, dynamic> _studentsForTest(
    Map<String, dynamic> data,
    Map<String, String> studentDirectory,
  ) {
    final rawStudents = Map<String, dynamic>.from(data["students"] ?? {})
      ..removeWhere((mobile, _) => !studentDirectory.containsKey(mobile));

    for (final mobile in studentDirectory.keys) {
      rawStudents.putIfAbsent(
        mobile,
        () => {
          "marks": "",
          "absent": true,
          "feedback": "",
          "type": "",
          "feedbackRead": true,
        },
      );
    }

    return rawStudents;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "Performance Analysis",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),

      body: Column(
        children: [
          /// FILTER (UNCHANGED)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedClass,
                  decoration: _inputDecoration("Class"),
                  items: AcademicCatalog.classValues.map((value) {
                    return DropdownMenuItem(
                      value: value,
                      child: Text(AcademicCatalog.classLabel(value)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        selectedClass = v;
                        selectedSubject = AcademicCatalog.baseSubjectsForClass(
                          v,
                        ).first;
                      });
                    }
                  },
                ),

                const SizedBox(height: 12),

                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _customSubjectsStream(),
                  builder: (context, snapshot) {
                    final subjects = [
                      ..._subjectsWithCustom(snapshot.data?.data()),
                      _mcqSubject,
                    ];
                    final value = subjects.contains(selectedSubject)
                        ? selectedSubject
                        : subjects.first;

                    if (value != selectedSubject) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => selectedSubject = value);
                        }
                      });
                    }

                    return DropdownButtonFormField<String>(
                      key: ValueKey("analysis-subject-$selectedClass-$value"),
                      initialValue: value,
                      decoration: _inputDecoration("Subject"),
                      items: subjects
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => selectedSubject = v);
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          /// DATA
          Expanded(
            child: selectedSubject == _mcqSubject
                ? _buildMcqAnalysis()
                : _buildProgressAnalysis(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressAnalysis() {
    return StreamBuilder<QuerySnapshot>(
      stream: _testsStream(),
      builder: (context, testSnap) {
        if (testSnap.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "Could not fetch performance records. Please try again shortly.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!testSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tests = testSnap.data!.docs;

        return StreamBuilder<QuerySnapshot>(
          stream: _studentsStream(),
          builder: (context, studentSnap) {
            if (studentSnap.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Could not fetch student list. Please try again shortly.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (!studentSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final studentDirectory = <String, String>{
              for (var doc in studentSnap.data!.docs)
                if ((doc.data() as Map<String, dynamic>)["active"] != false &&
                    AcademicCatalog.batchMatches(
                      doc.data() as Map<String, dynamic>,
                      selectedBatch,
                    ))
                  doc.id: doc["name"]?.toString() ?? "Unnamed",
            };

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 18),
              itemCount: tests.length,
              itemBuilder: (context, index) {
                final data = tests[index].data() as Map<String, dynamic>;
                final chapter = data["chapter"] ?? "";
                final totalMarks =
                    double.tryParse(data["totalMarks"]?.toString() ?? "0") ?? 0;

                final testDate = formatDate(data["date"]);
                final testReference = tests[index].reference;

                final students = _studentsForTest(data, studentDirectory);

                double total = 0;
                int appeared = 0;
                students.forEach((key, value) {
                  if (_isAbsent(value)) return;
                  appeared++;
                  total +=
                      double.tryParse(value["marks"]?.toString() ?? "0") ?? 0;
                });

                final avg = appeared == 0 ? 0.0 : total / appeared;

                final sortedStudents = students.entries.toList()
                  ..sort((a, b) {
                    final aAbsent = _isAbsent(a.value);
                    final bAbsent = _isAbsent(b.value);
                    if (aAbsent != bAbsent) return aAbsent ? 1 : -1;
                    final aMarks =
                        double.tryParse(a.value["marks"]?.toString() ?? "0") ??
                        0;
                    final bMarks =
                        double.tryParse(b.value["marks"]?.toString() ?? "0") ??
                        0;
                    return bMarks.compareTo(aMarks);
                  });

                final isExpanded = expandedIndex == index;

                final testTitle = chapter.toString().trim().isEmpty
                    ? "Test ${index + 1}"
                    : chapter.toString().trim();
                final maxLabel = totalMarks == 0
                    ? "Max not set"
                    : "Max ${_formatNumber(totalMarks)}";

                return _progressTestCard(
                  index: index,
                  isExpanded: isExpanded,
                  testTitle: testTitle,
                  testDate: testDate,
                  maxLabel: maxLabel,
                  totalMarks: totalMarks,
                  avg: avg,
                  appeared: appeared,
                  students: students,
                  sortedStudents: sortedStudents,
                  studentDirectory: studentDirectory,
                  testReference: testReference,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMcqAnalysis() {
    return StreamBuilder<QuerySnapshot>(
      stream: _mcqTestsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "Could not fetch MCQ analytics. Please try again shortly.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tests =
            snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return AcademicCatalog.mcqTargetClass(data) == selectedClass;
            }).toList()..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              return _dateFrom(
                bData["scheduledAt"],
              ).compareTo(_dateFrom(aData["scheduledAt"]));
            });

        if (tests.isEmpty) {
          return const Center(child: Text("No MCQ results available yet"));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 18),
          itemCount: tests.length,
          itemBuilder: (context, index) {
            final doc = tests[index];
            final data = doc.data() as Map<String, dynamic>;
            final isExpanded = expandedIndex == index;
            final scheduledAt = _dateFrom(data["scheduledAt"]);
            final totalMarks =
                double.tryParse(data["totalMarks"]?.toString() ?? "0") ?? 0;
            final summaryAppeared =
                int.tryParse(data["submissionCount"]?.toString() ?? "") ?? 0;
            final summaryTotalScore =
                double.tryParse(
                  data["totalSubmittedScore"]?.toString() ?? "",
                ) ??
                0.0;
            final summaryAverage = summaryAppeared == 0
                ? 0.0
                : summaryTotalScore / summaryAppeared;
            final header = Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.quiz_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data["chapterName"]?.toString() ?? "MCQ Test",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat("dd MMM yyyy").format(scheduledAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    "Max ${_formatNumber(totalMarks)}",
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            );

            return GestureDetector(
              onTap: () {
                setState(() {
                  expandedIndex = isExpanded ? null : index;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isExpanded
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.22)
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: isExpanded
                    ? StreamBuilder<QuerySnapshot>(
                        stream: doc.reference
                            .collection("results")
                            .orderBy("score", descending: true)
                            .orderBy("timeTakenSeconds")
                            .orderBy("submittedAt")
                            .limit(QueryLimits.mcqPreviewResults)
                            .snapshots(),
                        builder: (context, resultSnap) {
                          if (resultSnap.hasError) {
                            return const SizedBox.shrink();
                          }

                          if (!resultSnap.hasData) {
                            return const LinearProgressIndicator();
                          }

                          final results = resultSnap.data!.docs.map((
                            resultDoc,
                          ) {
                            final resultData =
                                resultDoc.data() as Map<String, dynamic>;
                            return computeMcqResult(data, resultData);
                          }).toList()..sort(compareMcqComputedResults);
                          final appeared = results.length;
                          final average = appeared == 0
                              ? 0.0
                              : results.fold<double>(
                                      0,
                                      (total, result) => total + result.score,
                                    ) /
                                    appeared;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              header,
                              if (isExpanded) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    _metricChip(
                                      "Average",
                                      average.toStringAsFixed(1),
                                      Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    _metricChip(
                                      "Appeared",
                                      "$appeared",
                                      Colors.teal,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (results.isEmpty)
                                  const Text(
                                    "Merit list will appear after submissions.",
                                  )
                                else
                                  ...results.asMap().entries.map((entry) {
                                    return _mcqResultTile(
                                      entry.key,
                                      entry.value,
                                      isTopper: entry.key == 0,
                                    );
                                  }),
                              ],
                            ],
                          );
                        },
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          if (summaryAppeared > 0) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _metricChip(
                                  "Average",
                                  summaryAverage.toStringAsFixed(1),
                                  Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                _metricChip(
                                  "Appeared",
                                  "$summaryAppeared",
                                  Colors.teal,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _progressTestCard({
    required int index,
    required bool isExpanded,
    required String testTitle,
    required String testDate,
    required String maxLabel,
    required double totalMarks,
    required double avg,
    required int appeared,
    required Map<String, dynamic> students,
    required List<MapEntry<String, dynamic>> sortedStudents,
    required Map<String, String> studentDirectory,
    required DocumentReference testReference,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          expandedIndex = isExpanded ? null : index;
        });
      },

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(16),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isExpanded
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.04),
          ),
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
                  height: 44,
                  width: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    "${index + 1}",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        testTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        testDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    maxLabel,
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == "delete") {
                      _deleteTest(testReference, testTitle);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: "delete",
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text("Delete test"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (isExpanded) ...[
              const SizedBox(height: 10),

              Row(
                children: [
                  _metricChip("Average", avg.toStringAsFixed(1), Colors.blue),
                  const SizedBox(width: 8),
                  _metricChip(
                    "Appeared",
                    "$appeared/${students.length}",
                    Colors.teal,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              ...sortedStudents.asMap().entries.map((entry) {
                final i = entry.key;
                final student = entry.value;

                final name = studentDirectory[student.key] ?? student.key;

                final marks =
                    double.tryParse(
                      student.value["marks"]?.toString() ?? "0",
                    ) ??
                    0;
                final studentData = Map<String, dynamic>.from(student.value);
                final feedback = studentData["feedback"]?.toString() ?? "";
                final isAbsent = _isAbsent(studentData);

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.04),
                    ),
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text("${i + 1}."),

                          const SizedBox(width: 10),

                          Expanded(
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          ),

                          Text(
                            isAbsent
                                ? "Ab"
                                : totalMarks == 0
                                ? _formatNumber(marks)
                                : "${_formatNumber(marks)}/${_formatNumber(totalMarks)}",
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),

                          IconButton(
                            tooltip: "Edit record",
                            icon: const Icon(Icons.edit_note),
                            onPressed: () => _editStudentRecord(
                              reference: testReference,
                              mobile: student.key,
                              name: name,
                              current: studentData,
                            ),
                          ),
                        ],
                      ),
                      if (feedback.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          feedback,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mcqResultTile(
    int index,
    McqComputedResult result, {
    required bool isTopper,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: isTopper ? 8 : 6),
      padding: EdgeInsets.all(isTopper ? 16 : 14),
      decoration: BoxDecoration(
        color: isTopper ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(isTopper ? 20 : 16),
        border: Border.all(
          color: isTopper
              ? const Color(0xFFF59E0B)
              : Colors.black.withValues(alpha: 0.04),
          width: isTopper ? 1.4 : 1,
        ),
        boxShadow: isTopper
            ? [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: isTopper ? 20 : 16,
            backgroundColor: isTopper
                ? const Color(0xFFF59E0B)
                : const Color(0xFFE2E8F0),
            child: Icon(
              isTopper ? Icons.emoji_events : Icons.person,
              color: isTopper ? Colors.white : const Color(0xFF475569),
              size: isTopper ? 22 : 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.studentName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isTopper ? 18 : 14,
                    fontWeight: isTopper ? FontWeight.w900 : FontWeight.w700,
                    color: isTopper
                        ? const Color(0xFF92400E)
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isTopper
                      ? "Topper • ${result.correctCount} correct • ${_formatTime(result.timeTakenSeconds)}"
                      : "#${index + 1} • ${result.correctCount} correct • ${_formatTime(result.timeTakenSeconds)}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isTopper
                        ? const Color(0xFFB45309)
                        : Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "${_formatNumber(result.score)}/${_formatNumber(result.totalMarks)}",
            style: TextStyle(
              color: isTopper
                  ? const Color(0xFF92400E)
                  : const Color(0xFF0F172A),
              fontSize: isTopper ? 16 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  DateTime _dateFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime(2000);
  }

  /// 🔥 Clean reusable decoration
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _metricChip(String label, String value, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        "$label: $value",
        style: TextStyle(
          color: color.shade700,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    if (seconds >= (1 << 30)) return "time not recorded";
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final secs = safeSeconds % 60;
    return "${minutes}m ${secs.toString().padLeft(2, "0")}s";
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}
