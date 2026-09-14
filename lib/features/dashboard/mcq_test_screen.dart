import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/query_limits.dart';
import '../../core/constants/academic_catalog.dart';
import '../../core/text/scientific_text_tools.dart';
import 'mcq_result_utils.dart';

class MCQTestScreen extends StatefulWidget {
  const MCQTestScreen({super.key});

  @override
  State<MCQTestScreen> createState() => _MCQTestScreenState();
}

class _MCQTestScreenState extends State<MCQTestScreen> {
  final _chapterController = TextEditingController();
  final _totalMarksController = TextEditingController();
  final _marksPerQuestionController = TextEditingController(text: "1");
  final _negativeMarksController = TextEditingController();
  final _secondsPerQuestionController = TextEditingController(text: "10");
  final _totalTimeController = TextEditingController();
  final List<_QuestionInput> _questions = [_QuestionInput()];

  String _selectedClass = AcademicCatalog.classValues.first;
  String _timingMode = "perQuestion";
  DateTime _scheduledAt = DateTime.now().add(const Duration(minutes: 5));
  bool _negativeEnabled = false;
  bool _saving = false;
  String? _editingTestId;
  String? _templateSourceId;

  @override
  void initState() {
    super.initState();
    _marksPerQuestionController.addListener(_recalculateDerivedFields);
    _secondsPerQuestionController.addListener(_recalculateDerivedFields);
    _recalculateDerivedFields();
  }

  @override
  void dispose() {
    _chapterController.dispose();
    _totalMarksController.dispose();
    _marksPerQuestionController.dispose();
    _negativeMarksController.dispose();
    _secondsPerQuestionController.dispose();
    _totalTimeController.dispose();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  void _recalculateDerivedFields() {
    final marksPerQuestion =
        double.tryParse(_marksPerQuestionController.text.trim()) ?? 0;
    final secondsPerQuestion =
        int.tryParse(_secondsPerQuestionController.text.trim()) ?? 0;
    final questionCount = _questions.length;

    final totalMarks = marksPerQuestion * questionCount;
    final totalMarksText = _formatNumber(totalMarks);
    if (_totalMarksController.text != totalMarksText) {
      _totalMarksController.text = totalMarksText;
    }

    if (_timingMode == "perQuestion") {
      final totalSeconds = secondsPerQuestion * questionCount;
      final minutes = totalSeconds <= 0 ? 0 : (totalSeconds / 60).ceil();
      final totalTimeText = minutes == 0 ? "" : minutes.toString();
      if (_totalTimeController.text != totalTimeText) {
        _totalTimeController.text = totalTimeText;
      }
    }
  }

  String _formatNumber(num value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  Future<void> _pickSchedule(StateSetter setSheetState) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null) return;

    setSheetState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _saveTest(
    BuildContext sheetContext,
    StateSetter setSheetState,
  ) async {
    FocusScope.of(sheetContext).unfocus();

    final chapter = _chapterController.text.trim();
    final marksPerQuestion = double.tryParse(
      _marksPerQuestionController.text.trim(),
    );
    final negativeMarks = _negativeEnabled
        ? (double.tryParse(_negativeMarksController.text.trim()) ?? 0)
        : 0.0;
    final secondsPerQuestion = _timingMode == "perQuestion"
        ? int.tryParse(_secondsPerQuestionController.text.trim())
        : null;
    final totalTime = int.tryParse(_totalTimeController.text.trim());
    final questions = _questions
        .map((question) => question.toData())
        .whereType<Map<String, dynamic>>()
        .toList();

    if (chapter.isEmpty || marksPerQuestion == null || totalTime == null) {
      _showSnack("Fill test chapter, marks/question and time");
      return;
    }

    if (marksPerQuestion <= 0 || totalTime <= 0) {
      _showSnack("Marks and time must be greater than zero");
      return;
    }

    if (_timingMode == "perQuestion" &&
        (secondsPerQuestion == null || secondsPerQuestion <= 0)) {
      _showSnack("Enter valid seconds/question");
      return;
    }

    if (questions.length != _questions.length) {
      _showSnack("Complete every question and all four options");
      return;
    }

    final targetClass =
        AcademicCatalog.mcqClassForChapter(chapter) ?? _selectedClass;

    void updateSaving(bool value) {
      if (!mounted) return;
      setState(() => _saving = value);
      setSheetState(() {});
    }

    updateSaving(true);

    final data = <String, dynamic>{
      "chapterName": chapter,
      "class": targetClass,
      "targetBatch": AcademicCatalog.regularBatch,
      "status": _editingTestId == null ? "draft" : FieldValue.delete(),
      "totalMarks": marksPerQuestion * questions.length,
      "marksPerQuestion": marksPerQuestion,
      "negativeMarkingEnabled": _negativeEnabled,
      "negativeMarksPerQuestion": negativeMarks,
      "timingMode": _timingMode,
      "testLocation": "tuition",
      "secondsPerQuestion": secondsPerQuestion ?? 0,
      "totalTimeMinutes": totalTime,
      "scheduledAt": Timestamp.fromDate(_scheduledAt),
      "questions": questions,
      "templateId": _templateSourceId,
      "updatedAt": FieldValue.serverTimestamp(),
    };

    try {
      if (_editingTestId == null) {
        data["status"] = "draft";
        data["createdAt"] = FieldValue.serverTimestamp();
        final testRef = await FirebaseFirestore.instance
            .collection("mcq_tests")
            .add(data);
        final templateId = await _saveReusableTemplate(
          testRef.id,
          data,
          questions,
        );
        await testRef.set({"templateId": templateId}, SetOptions(merge: true));
      } else {
        data.remove("status");
        await FirebaseFirestore.instance
            .collection("mcq_tests")
            .doc(_editingTestId)
            .set(data, SetOptions(merge: true));
        await _refreshExistingResultsForTest(_editingTestId!, data);
        final templateId = await _saveReusableTemplate(
          _editingTestId!,
          data,
          questions,
        );
        await FirebaseFirestore.instance
            .collection("mcq_tests")
            .doc(_editingTestId)
            .set({"templateId": templateId}, SetOptions(merge: true));
      }
    } catch (error) {
      if (!mounted) return;
      if (sheetContext.mounted) {
        updateSaving(false);
      } else {
        setState(() => _saving = false);
      }
      _showSnack(_saveErrorMessage(error));
      return;
    }

    if (!mounted) return;
    if (sheetContext.mounted) {
      updateSaving(false);
      Navigator.of(sheetContext).pop();
    } else {
      setState(() => _saving = false);
    }
    _showSnack(_editingTestId == null ? "Draft test saved" : "Test updated");
  }

  Future<String> _saveReusableTemplate(
    String testId,
    Map<String, dynamic> testData,
    List<Map<String, dynamic>> questions,
  ) async {
    final templateId = _templateSourceId ?? testId;
    final templateRef = FirebaseFirestore.instance
        .collection("mcq_test_templates")
        .doc(templateId);
    await templateRef.set({
      "chapterName": testData["chapterName"],
      "class": testData["class"],
      "targetBatch": testData["targetBatch"],
      "totalMarks": testData["totalMarks"],
      "marksPerQuestion": testData["marksPerQuestion"],
      "negativeMarkingEnabled": testData["negativeMarkingEnabled"],
      "negativeMarksPerQuestion": testData["negativeMarksPerQuestion"],
      "timingMode": testData["timingMode"],
      "testLocation": testData["testLocation"],
      "secondsPerQuestion": testData["secondsPerQuestion"],
      "totalTimeMinutes": testData["totalTimeMinutes"],
      "questions": questions,
      "sourceTestId": testId,
      "questionCount": questions.length,
      "updatedAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _templateSourceId = templateId;
    return templateId;
  }

  String _saveErrorMessage(Object error) {
    if (error is FirebaseException) {
      return error.message?.trim().isNotEmpty == true
          ? "Could not save test: ${error.message}"
          : "Could not save test. Please check Firebase permissions.";
    }
    return "Could not save test. Please try again.";
  }

  Future<void> _refreshExistingResultsForTest(
    String testId,
    Map<String, dynamic> testData,
  ) async {
    final resultsSnap = await FirebaseFirestore.instance
        .collection("mcq_tests")
        .doc(testId)
        .collection("results")
        .get();
    if (resultsSnap.docs.isEmpty) return;

    var batch = FirebaseFirestore.instance.batch();
    var batchWrites = 0;

    Future<void> commitBatchIfNeeded({bool force = false}) async {
      if (batchWrites == 0 || (!force && batchWrites < 450)) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      batchWrites = 0;
    }

    for (final doc in resultsSnap.docs) {
      final computed = computeMcqResult(testData, doc.data());
      batch.set(doc.reference, {
        "score": computed.score,
        "correctCount": computed.correctCount,
        "wrongCount": computed.wrongCount,
        "unansweredCount": computed.unansweredCount,
        "totalQuestions": computed.totalQuestions,
        "totalMarks": computed.totalMarks,
        "recomputedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batchWrites++;
      await commitBatchIfNeeded();
    }

    await commitBatchIfNeeded(force: true);
  }

  void _resetForm() {
    _chapterController.clear();
    _marksPerQuestionController.text = "1";
    _negativeMarksController.clear();
    _secondsPerQuestionController.text = "10";
    _totalTimeController.clear();
    _selectedClass = AcademicCatalog.classValues.first;
    _timingMode = "perQuestion";
    _negativeEnabled = false;
    _editingTestId = null;
    _templateSourceId = null;
    _scheduledAt = DateTime.now().add(const Duration(minutes: 5));
    for (final question in _questions) {
      question.dispose();
    }
    _questions
      ..clear()
      ..add(_QuestionInput());
    _recalculateDerivedFields();
  }

  void _resetFormAfterSheetDismissed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetForm();
    });
  }

  void _loadTestForEdit(String id, Map<String, dynamic> data) {
    _resetForm();
    _editingTestId = id;
    _templateSourceId = data["templateId"]?.toString();
    _chapterController.text = data["chapterName"]?.toString() ?? "";
    _selectedClass = AcademicCatalog.mcqTargetClass(
      data,
      fallback: AcademicCatalog.classValues.first,
    );
    _timingMode = data["timingMode"]?.toString() == "totalOnly"
        ? "totalOnly"
        : "perQuestion";
    _negativeEnabled = data["negativeMarkingEnabled"] == true;
    _marksPerQuestionController.text = _formatNumber(
      double.tryParse(data["marksPerQuestion"]?.toString() ?? "") ?? 1,
    );
    _negativeMarksController.text = _negativeEnabled
        ? _formatNumber(
            double.tryParse(
                  data["negativeMarksPerQuestion"]?.toString() ?? "",
                ) ??
                0,
          )
        : "";
    _secondsPerQuestionController.text =
        (int.tryParse(data["secondsPerQuestion"]?.toString() ?? "") ?? 10)
            .toString();
    _totalTimeController.text =
        (int.tryParse(data["totalTimeMinutes"]?.toString() ?? "") ?? 10)
            .toString();
    final scheduled = data["scheduledAt"];
    if (scheduled is Timestamp) _scheduledAt = scheduled.toDate();

    final rawQuestions = data["questions"];
    if (rawQuestions is List && rawQuestions.isNotEmpty) {
      for (final question in _questions) {
        question.dispose();
      }
      _questions.clear();
      for (final raw in rawQuestions.whereType<Map>()) {
        _questions.add(_QuestionInput.fromData(Map<String, dynamic>.from(raw)));
      }
    }
    _recalculateDerivedFields();
  }

  void _loadReusableTest({
    required Map<String, dynamic> data,
    String? templateSourceId,
    String? sourceTestId,
  }) {
    _resetForm();
    _chapterController.text = data["chapterName"]?.toString() ?? "";
    _selectedClass = AcademicCatalog.mcqTargetClass(
      data,
      fallback: AcademicCatalog.classValues.first,
    );
    _timingMode = data["timingMode"]?.toString() == "totalOnly"
        ? "totalOnly"
        : "perQuestion";
    _negativeEnabled = data["negativeMarkingEnabled"] == true;
    _marksPerQuestionController.text = _formatNumber(
      double.tryParse(data["marksPerQuestion"]?.toString() ?? "") ?? 1,
    );
    _negativeMarksController.text = _negativeEnabled
        ? _formatNumber(
            double.tryParse(
                  data["negativeMarksPerQuestion"]?.toString() ?? "",
                ) ??
                0,
          )
        : "";
    _secondsPerQuestionController.text =
        (int.tryParse(data["secondsPerQuestion"]?.toString() ?? "") ?? 10)
            .toString();
    _totalTimeController.text =
        (int.tryParse(data["totalTimeMinutes"]?.toString() ?? "") ?? 10)
            .toString();
    _scheduledAt = DateTime.now().add(const Duration(minutes: 5));
    _templateSourceId = templateSourceId ?? sourceTestId;

    final rawQuestions = data["questions"];
    if (rawQuestions is List && rawQuestions.isNotEmpty) {
      for (final question in _questions) {
        question.dispose();
      }
      _questions.clear();
      for (final raw in rawQuestions.whereType<Map>()) {
        _questions.add(_QuestionInput.fromData(Map<String, dynamic>.from(raw)));
      }
    }
    _recalculateDerivedFields();
  }

  Future<void> _showTestSheet({
    String? id,
    Map<String, dynamic>? data,
    bool reuse = false,
  }) async {
    if (reuse && data != null) {
      _loadReusableTest(data: data, sourceTestId: id);
    } else if (id == null || data == null) {
      _resetForm();
    } else {
      _loadTestForEdit(id, data);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void refresh() {
              _recalculateDerivedFields();
              setSheetState(() {});
            }

            return Container(
              color: const Color(0xFFF8FAFC),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 16,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: "Back",
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            reuse
                                ? "Reuse MCQ Test"
                                : _editingTestId == null
                                ? "Create MCQ Test"
                                : "Edit MCQ Test",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_editingTestId == null) ...[
                      _templateImportPanel(refresh),
                      const SizedBox(height: 12),
                    ],
                    _formSection(
                      color: const Color(0xFFEFF6FF),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _RegularBatchNotice(),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedClass,
                            decoration: _decoration("Class", Icons.school),
                            items: AcademicCatalog.classValues
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      AcademicCatalog.classLabel(value),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              _selectedClass =
                                  value ?? AcademicCatalog.classValues.first;
                              refresh();
                            },
                          ),
                          const SizedBox(height: 10),
                          _field(
                            _chapterController,
                            "Test chapter name",
                            Icons.menu_book,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _formSection(
                      color: const Color(0xFFF0FDF4),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _numberField(
                                  _marksPerQuestionController,
                                  "Marks/Question",
                                  Icons.add_circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _readOnlyField(
                                  _totalMarksController,
                                  "Total marks",
                                  Icons.score,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _negativeEnabled,
                            title: const Text("Negative marking"),
                            subtitle: const Text(
                              "Leave off for no negative marking",
                            ),
                            onChanged: (value) {
                              _negativeEnabled = value;
                              if (!value) _negativeMarksController.clear();
                              refresh();
                            },
                          ),
                          if (_negativeEnabled) ...[
                            _numberField(
                              _negativeMarksController,
                              "Negative marks/question",
                              Icons.remove_circle,
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _formSection(
                      color: const Color(0xFFFFFBEB),
                      child: Column(
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: "perQuestion",
                                icon: Icon(Icons.timer),
                                label: Text("Per question"),
                              ),
                              ButtonSegment(
                                value: "totalOnly",
                                icon: Icon(Icons.hourglass_bottom),
                                label: Text("Total time"),
                              ),
                            ],
                            selected: {_timingMode},
                            onSelectionChanged: (value) {
                              _timingMode = value.first;
                              refresh();
                            },
                          ),
                          const SizedBox(height: 10),
                          if (_timingMode == "perQuestion") ...[
                            _numberField(
                              _secondsPerQuestionController,
                              "Seconds/Question",
                              Icons.timer,
                              integerOnly: true,
                            ),
                            const SizedBox(height: 10),
                            _readOnlyField(
                              _totalTimeController,
                              "Total time in minutes",
                              Icons.schedule,
                            ),
                          ] else
                            _numberField(
                              _totalTimeController,
                              "Total time in minutes",
                              Icons.schedule,
                              integerOnly: true,
                            ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _pickSchedule(setSheetState),
                              icon: const Icon(Icons.event),
                              label: Text(
                                DateFormat(
                                  "dd MMM yyyy • hh:mm a",
                                ).format(_scheduledAt),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Questions",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _questionCountBanner(),
                    const SizedBox(height: 8),
                    ..._questions.asMap().entries.map((entry) {
                      return _QuestionEditor(
                        index: entry.key,
                        question: entry.value,
                        canRemove: _questions.length > 1,
                        onAddAfter: () {
                          _questions.insert(entry.key + 1, _QuestionInput());
                          refresh();
                        },
                        onRemove: () {
                          final removed = _questions.removeAt(entry.key);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            removed.dispose();
                          });
                          refresh();
                        },
                        onChanged: refresh,
                      );
                    }),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _saveTest(context, setSheetState),
                        icon: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _editingTestId == null
                              ? "Save Draft"
                              : "Save Changes",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) _resetFormAfterSheetDismissed();
  }

  Widget _formSection({required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }

  Widget _templateImportPanel(VoidCallback refresh) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.library_books, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Start from a saved test and assign it to any class.",
              style: TextStyle(
                color: Color(0xFF1E3A8A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _showTemplatePicker(refresh),
            child: const Text("Use saved"),
          ),
        ],
      ),
    );
  }

  Future<void> _showTemplatePicker(VoidCallback refresh) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Material(
              color: const Color(0xFFF5F7FB),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection("mcq_test_templates")
                    .orderBy("updatedAt", descending: true)
                    .limit(QueryLimits.mcqTests)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "Saved Tests",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: "Close",
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (docs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              "No saved reusable tests yet. Save any MCQ test once and it will appear here.",
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ...docs.map((doc) {
                          final data = doc.data();
                          final questions = data["questions"];
                          final questionCount = questions is List
                              ? questions.length
                              : 0;
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              title: Text(
                                data["chapterName"]?.toString() ?? "MCQ Test",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                "${AcademicCatalog.classLabel(AcademicCatalog.mcqTargetClass(data, fallback: ""))} • $questionCount questions",
                              ),
                              trailing: const Icon(Icons.arrow_forward),
                              onTap: () {
                                _loadReusableTest(
                                  data: data,
                                  templateSourceId: doc.id,
                                );
                                refresh();
                                Navigator.pop(context);
                              },
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _questionCountBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD6FE)),
      ),
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.format_list_numbered,
              color: Color(0xFF6D28D9),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "${_questions.length} question${_questions.length == 1 ? "" : "s"} selected so far",
              style: const TextStyle(
                color: Color(0xFF4C1D95),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: _decoration(label, icon),
    );
  }

  Widget _readOnlyField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: _decoration(label, icon),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool integerOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          integerOnly ? RegExp(r"[0-9]") : RegExp(r"[0-9.]"),
        ),
      ],
      decoration: _decoration(label, icon),
    );
  }

  Future<void> _deleteTest(String id) async {
    await FirebaseFirestore.instance.collection("mcq_tests").doc(id).delete();
    if (!mounted) return;
    _showSnack("Test deleted");
  }

  Future<void> _cancelReleasedTest(String id, Map<String, dynamic> data) async {
    final chapter = data["chapterName"]?.toString() ?? "MCQ Test";
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel test?"),
        content: Text(
          "This will keep \"$chapter\" as a draft, clear submitted results from the merit list, and remove its release notification. You can edit and release it again later.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Keep Released"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Cancel Test"),
          ),
        ],
      ),
    );
    if (shouldCancel != true) return;

    final testRef = FirebaseFirestore.instance.collection("mcq_tests").doc(id);
    final resultsSnap = await testRef.collection("results").get();
    var batch = FirebaseFirestore.instance.batch();
    var batchWrites = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (batchWrites == 0 || (!force && batchWrites < 450)) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      batchWrites = 0;
    }

    for (final result in resultsSnap.docs) {
      batch.delete(result.reference);
      batchWrites++;
      await commitIfNeeded();
    }

    final updatesSnap = await FirebaseFirestore.instance
        .collection("updates")
        .where("type", isEqualTo: "mcq_test")
        .where("testId", isEqualTo: id)
        .get();
    for (final update in updatesSnap.docs) {
      batch.delete(update.reference);
      batchWrites++;
      await commitIfNeeded();
    }

    batch.set(testRef, {
      "status": "draft",
      "submissionCount": 0,
      "totalSubmittedScore": 0,
      "topScore": 0,
      "cancelledAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batchWrites++;
    await commitIfNeeded(force: true);

    if (!mounted) return;
    _showSnack("Test cancelled. Merit list cleared and draft preserved.");
  }

  Future<void> _releaseTest(String id, Map<String, dynamic> data) async {
    final scheduledAt = data["scheduledAt"] is Timestamp
        ? (data["scheduledAt"] as Timestamp).toDate()
        : DateTime.now();
    final target = AcademicCatalog.mcqTargetClass(data);
    final targetBatch = AcademicCatalog.mcqTargetBatch(data);
    final chapter = data["chapterName"]?.toString() ?? "MCQ Test";

    await FirebaseFirestore.instance.collection("mcq_tests").doc(id).set({
      "class": target,
      "status": "released",
      "submissionCount": data["submissionCount"] ?? 0,
      "totalSubmittedScore": data["totalSubmittedScore"] ?? 0,
      "topScore": data["topScore"] ?? 0,
      "releasedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection("updates").doc("mcq_$id").set({
      "title": "New MCQ Test Available",
      "message":
          "$chapter test is available for ${AcademicCatalog.classLabel(target)} • ${AcademicCatalog.batchLabel(targetBatch)}.",
      "target": target,
      "targetLabel": AcademicCatalog.classLabel(target),
      "targetBatch": targetBatch,
      "targetBatchLabel": AcademicCatalog.batchLabel(targetBatch),
      "scheduledAt": Timestamp.now(),
      "type": "mcq_test",
      "testId": id,
      "questionCount": mcqQuestionsFrom(data).length,
      "releaseTimeLabel": DateFormat(
        "dd MMM yyyy, hh:mm a",
      ).format(scheduledAt),
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    _showSnack(
      "Test released and ${AcademicCatalog.batchLabel(targetBatch)} notified",
    );
  }

  Future<void> _showTestPreview(String id, Map<String, dynamic> data) async {
    final questions = mcqQuestionsFrom(data);
    final scheduledAt = _dateFrom(data["scheduledAt"]);
    final title = data["chapterName"]?.toString() ?? "MCQ Test";

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.62,
          maxChildSize: 0.96,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection("mcq_tests")
                    .doc(id)
                    .collection("results")
                    .orderBy("score", descending: true)
                    .orderBy("timeTakenSeconds")
                    .orderBy("submittedAt")
                    .limit(QueryLimits.mcqPreviewResults)
                    .get(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "Could not fetch MCQ results. Please try again shortly.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final results = snapshot.hasData
                      ? (snapshot.data!.docs
                            .where((doc) => isMeritMcqResult(doc.data()))
                            .map((doc) => computeMcqResult(data, doc.data()))
                            .toList()
                          ..sort(compareMcqComputedResults))
                      : <McqComputedResult>[];
                  final average = results.isEmpty
                      ? 0.0
                      : results.fold<double>(
                              0,
                              (total, item) => total + item.score,
                            ) /
                            results.length;
                  final topScore = results.isEmpty ? 0.0 : results.first.score;

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              "View Test",
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF171717), Color(0xFF1F4F46)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 22,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "${AcademicCatalog.classLabel(AcademicCatalog.mcqTargetClass(data, fallback: ""))} • ${DateFormat("dd MMM yyyy, hh:mm a").format(scheduledAt)}",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _PreviewStat(
                                  label: "Questions",
                                  value: questions.length.toString(),
                                ),
                                _PreviewStat(
                                  label: "Attempts",
                                  value: results.length.toString(),
                                ),
                                _PreviewStat(
                                  label: "Top",
                                  value: _formatNumber(topScore),
                                ),
                                _PreviewStat(
                                  label: "Average",
                                  value: _formatNumber(average),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Question Paper",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...questions.asMap().entries.map((entry) {
                        final question = entry.value;
                        final optionsRaw = question["options"];
                        final options = optionsRaw is List
                            ? optionsRaw
                                  .map((value) => value.toString())
                                  .toList()
                            : <String>[];
                        final correctIndex =
                            int.tryParse(
                              question["correctIndex"]?.toString() ?? "",
                            ) ??
                            0;

                        return _PreviewQuestionCard(
                          index: entry.key,
                          question: question["question"]?.toString() ?? "",
                          options: options,
                          correctIndex: correctIndex,
                        );
                      }),
                      const SizedBox(height: 10),
                      const Text(
                        "Submitted Results",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!snapshot.hasData)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (results.isEmpty)
                        _PreviewEmptyResults()
                      else
                        ...results.asMap().entries.map((entry) {
                          final result = entry.value;
                          return _PreviewResultTile(
                            rank: entry.key + 1,
                            result: result,
                            totalMarks:
                                double.tryParse(
                                  data["totalMarks"]?.toString() ?? "",
                                ) ??
                                result.totalMarks,
                          );
                        }),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPrivateReopenSheet(
    String id,
    Map<String, dynamic> data,
  ) async {
    final targetClass = AcademicCatalog.mcqTargetClass(data, fallback: "");
    final targetBatch = AcademicCatalog.mcqTargetBatch(data);
    final durationController = TextEditingController(
      text: (int.tryParse(data["totalTimeMinutes"]?.toString() ?? "") ?? 40)
          .clamp(1, 240)
          .toString(),
    );
    final reasonController = TextEditingController();
    String? selectedMobile;

    Future<List<_ReopenStudentOption>> loadStudents() async {
      final studentsSnap = await FirebaseFirestore.instance
          .collection("users")
          .where("role", isEqualTo: "student")
          .where("class", isEqualTo: targetClass)
          .orderBy("name")
          .get();
      final resultsSnap = await FirebaseFirestore.instance
          .collection("mcq_tests")
          .doc(id)
          .collection("results")
          .get();
      final submittedMobiles = resultsSnap.docs
          .where((doc) => isMeritMcqResult(doc.data()))
          .map((doc) => doc.id)
          .toSet();

      return studentsSnap.docs
          .where((doc) {
            final student = doc.data();
            return student["active"] != false &&
                AcademicCatalog.batchMatches(student, targetBatch);
          })
          .map((doc) {
            final student = doc.data();
            return _ReopenStudentOption(
              mobile: doc.id,
              name: student["name"]?.toString().trim().isNotEmpty == true
                  ? student["name"].toString()
                  : doc.id,
              submitted: submittedMobiles.contains(doc.id),
            );
          })
          .toList();
    }

    final studentsFuture = loadStudents();

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.82,
              minChildSize: 0.52,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: FutureBuilder<List<_ReopenStudentOption>>(
                    future: studentsFuture,
                    builder: (context, snapshot) {
                      final students = snapshot.data ?? [];
                      _ReopenStudentOption? selectedStudent;
                      for (final student in students) {
                        if (student.mobile == selectedMobile) {
                          selectedStudent = student;
                          break;
                        }
                      }

                      return ListView(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          18,
                          16,
                          18,
                          MediaQuery.of(context).viewInsets.bottom + 24,
                        ),
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context, false),
                                icon: const Icon(Icons.close),
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text(
                                  "Reopen for Student",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock_person,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Creates a private attempt only for the selected student. No class notification or update is posted.",
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: durationController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: "Private attempt window (minutes)",
                              prefixIcon: Icon(Icons.timer),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: reasonController,
                            decoration: const InputDecoration(
                              labelText: "Reason or note (optional)",
                              prefixIcon: Icon(Icons.note_alt),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Select Student",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (snapshot.hasError)
                            const Padding(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                "Could not fetch students. Please try again shortly.",
                                textAlign: TextAlign.center,
                              ),
                            )
                          else if (!snapshot.hasData)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (students.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                "No active students found for this class and batch.",
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            ...students.map((student) {
                              final selected = selectedMobile == student.mobile;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: student.submitted
                                      ? null
                                      : () {
                                          setSheetState(() {
                                            selectedMobile = student.mobile;
                                          });
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: selected
                                            ? const Color(0xFF2563EB)
                                            : Colors.black.withValues(
                                                alpha: 0.06,
                                              ),
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          student.submitted
                                              ? Icons.check_circle
                                              : selected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          color: student.submitted
                                              ? Colors.green
                                              : selected
                                              ? const Color(0xFF2563EB)
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                student.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                student.submitted
                                                    ? "Already submitted"
                                                    : student.mobile,
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed:
                                  selectedStudent == null ||
                                      selectedStudent.submitted
                                  ? null
                                  : () async {
                                      final student = selectedStudent!;
                                      final minutes =
                                          int.tryParse(
                                            durationController.text.trim(),
                                          ) ??
                                          0;
                                      if (minutes <= 0) return;
                                      final now = DateTime.now();
                                      final testRef = FirebaseFirestore.instance
                                          .collection("mcq_tests")
                                          .doc(id);
                                      final requestRef = testRef
                                          .collection("reopenRequests")
                                          .doc(student.mobile);
                                      await requestRef.set({
                                        "active": true,
                                        "mobile": student.mobile,
                                        "studentName": student.name,
                                        "class": targetClass,
                                        "targetBatch": targetBatch,
                                        "durationMinutes": minutes,
                                        "availableFrom": Timestamp.fromDate(
                                          now,
                                        ),
                                        "availableUntil": Timestamp.fromDate(
                                          now.add(Duration(minutes: minutes)),
                                        ),
                                        "reason": reasonController.text.trim(),
                                        "createdAt":
                                            FieldValue.serverTimestamp(),
                                        "updatedAt":
                                            FieldValue.serverTimestamp(),
                                      }, SetOptions(merge: true));
                                      await testRef.set({
                                        "privateReopenMobiles":
                                            FieldValue.arrayUnion([
                                              student.mobile,
                                            ]),
                                        "updatedAt":
                                            FieldValue.serverTimestamp(),
                                      }, SetOptions(merge: true));
                                      if (context.mounted) {
                                        Navigator.pop(context, true);
                                      }
                                    },
                              icon: const Icon(Icons.lock_open),
                              label: const Text("Start Private Attempt"),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );

    durationController.dispose();
    reasonController.dispose();

    if (created == true && mounted) {
      _showSnack("Private attempt started for selected student.");
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("MCQ Tests")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showTestSheet,
        icon: const Icon(Icons.add),
        label: const Text("Create Test"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("mcq_tests")
            .orderBy("scheduledAt", descending: true)
            .limit(QueryLimits.mcqTests)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Could not fetch MCQ tests. Please try again shortly.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No MCQ tests yet"));
          }

          final groupedDocs = _groupTestsByClass(docs);
          final classValues = groupedDocs.keys.toList();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: classValues.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final classValue = classValues[index];
              return _ClassTestSection(
                classValue: classValue,
                docs: groupedDocs[classValue]!,
                buildCard: (doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _TestCard(
                    id: doc.id,
                    data: data,
                    onEdit: () => _showTestSheet(id: doc.id, data: data),
                    onReuse: () =>
                        _showTestSheet(id: doc.id, data: data, reuse: true),
                    onRelease: () => _releaseTest(doc.id, data),
                    onCancel: () => _cancelReleasedTest(doc.id, data),
                    onDelete: () => _deleteTest(doc.id),
                    onView: () => _showTestPreview(doc.id, data),
                    onReopen: () => _showPrivateReopenSheet(doc.id, data),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  DateTime _dateFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime(2000);
  }

  Map<String, List<QueryDocumentSnapshot>> _groupTestsByClass(
    List<QueryDocumentSnapshot> docs,
  ) {
    final grouped = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final classValue = AcademicCatalog.mcqTargetClass(
        data,
        fallback: AcademicCatalog.classValues.first,
      );
      grouped.putIfAbsent(classValue, () => []).add(doc);
    }

    final ordered = <String, List<QueryDocumentSnapshot>>{};
    for (final classValue in AcademicCatalog.classValues.reversed) {
      final classDocs = grouped.remove(classValue);
      if (classDocs != null && classDocs.isNotEmpty) {
        ordered[classValue] = classDocs;
      }
    }
    ordered.addAll(grouped);
    return ordered;
  }
}

class _QuestionInput {
  _QuestionInput();

  _QuestionInput.fromData(Map<String, dynamic> data) {
    questionController.text = data["question"]?.toString() ?? "";
    final rawOptions = data["options"];
    final options = rawOptions is List ? rawOptions : const [];
    for (var i = 0; i < optionControllers.length; i++) {
      optionControllers[i].text = i < options.length
          ? options[i].toString()
          : "";
    }
    correctIndex = int.tryParse(data["correctIndex"]?.toString() ?? "") ?? 0;
  }

  final questionController = TextEditingController();
  final optionControllers = List.generate(4, (_) => TextEditingController());
  int correctIndex = 0;

  Map<String, dynamic>? toData() {
    final question = questionController.text.trim();
    final options = optionControllers
        .map((controller) => controller.text.trim())
        .toList();

    if (question.isEmpty || options.any((option) => option.isEmpty)) {
      return null;
    }

    return {
      "question": question,
      "options": options,
      "correctIndex": correctIndex,
    };
  }

  void dispose() {
    questionController.dispose();
    for (final controller in optionControllers) {
      controller.dispose();
    }
  }
}

class _ReopenStudentOption {
  const _ReopenStudentOption({
    required this.mobile,
    required this.name,
    required this.submitted,
  });

  final String mobile;
  final String name;
  final bool submitted;
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    required this.index,
    required this.question,
    required this.canRemove,
    required this.onAddAfter,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _QuestionInput question;
  final bool canRemove;
  final VoidCallback onAddAfter;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Question ${index + 1}",
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: onAddAfter,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text("Add next"),
              ),
              if (canRemove)
                IconButton(onPressed: onRemove, icon: const Icon(Icons.close)),
            ],
          ),
          MathTextField(
            controller: question.questionController,
            label: "Question",
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          ...List.generate(4, (optionIndex) {
            final isCorrect = question.correctIndex == optionIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: "Mark correct answer",
                    onPressed: () {
                      question.correctIndex = optionIndex;
                      onChanged();
                    },
                    icon: Icon(
                      isCorrect
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isCorrect ? Colors.green : Colors.grey,
                    ),
                  ),
                  Expanded(
                    child: MathTextField(
                      controller: question.optionControllers[optionIndex],
                      label: "Option ${optionIndex + 1}",
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class MathTextField extends StatefulWidget {
  const MathTextField({
    super.key,
    required this.controller,
    required this.label,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int minLines;
  final int maxLines;

  @override
  State<MathTextField> createState() => _MathTextFieldState();
}

class _MathTextFieldState extends State<MathTextField> {
  static const _scriptSymbols = ["₂", "₃", "₄", "²", "³", "⁺", "⁻"];
  static const _chemistrySymbols = [
    "₀",
    "₁",
    "₂",
    "₃",
    "₄",
    "₅",
    "₆",
    "₇",
    "₈",
    "₉",
    "⁺",
    "⁻",
    "→",
    "⇌",
  ];
  static const _mathSymbols = [
    "√",
    "∛",
    "π",
    "∞",
    "±",
    "×",
    "÷",
    "≤",
    "≥",
    "≠",
    "Σ",
    "½",
    "¼",
  ];
  static const _greekSymbols = [
    "α",
    "β",
    "γ",
    "δ",
    "θ",
    "λ",
    "μ",
    "π",
    "σ",
    "Ω",
    "Δ",
  ];

  bool _showToolbar = false;
  ScientificScriptMode _mode = ScientificScriptMode.normal;

  void _insert(String value) {
    insertScientificText(widget.controller, value, mode: _mode);
  }

  void _convertSelection(ScientificScriptMode mode) {
    convertSelectedScientificText(widget.controller, mode);
  }

  void _convertFormula() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final start = selection.start;
      final end = selection.end;
      final replacement = convertFormulaDigitsToSubscript(
        text.substring(start, end),
      );
      widget.controller.value = TextEditingValue(
        text: text.replaceRange(start, end, replacement),
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + replacement.length,
        ),
      );
      return;
    }

    widget.controller.value = TextEditingValue(
      text: convertFormulaDigitsToSubscript(text),
      selection: TextSelection.collapsed(
        offset: convertFormulaDigitsToSubscript(text).length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          inputFormatters: [ScientificScriptInputFormatter(_mode)],
          textInputAction: widget.maxLines > 1
              ? TextInputAction.newline
              : TextInputAction.next,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixIcon: IconButton(
              tooltip: "Scientific input",
              onPressed: () => setState(() => _showToolbar = !_showToolbar),
              icon: Icon(
                Icons.functions,
                color: _showToolbar ? const Color(0xFF2563EB) : null,
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _showToolbar
              ? Padding(
                  key: const ValueKey("math-toolbar"),
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _scriptModeButton(
                          "Normal",
                          ScientificScriptMode.normal,
                        ),
                        _scriptModeButton(
                          "Subscript",
                          ScientificScriptMode.subscript,
                        ),
                        _scriptModeButton(
                          "Superscript",
                          ScientificScriptMode.superscript,
                        ),
                        _toolbarAction("x₂", () {
                          _convertSelection(ScientificScriptMode.subscript);
                        }),
                        _toolbarAction("x²", () {
                          _convertSelection(ScientificScriptMode.superscript);
                        }),
                        _toolbarAction("Formula", _convertFormula),
                        _symbolGroup("Scripts", _scriptSymbols),
                        _symbolGroup("Chemistry", _chemistrySymbols),
                        _symbolGroup("Math", _mathSymbols),
                        _symbolGroup("Greek", _greekSymbols),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _scriptModeButton(String label, ScientificScriptMode mode) {
    final active = _mode == mode;
    return ActionChip(
      label: Text(label),
      avatar: Icon(
        active ? Icons.check_circle_rounded : Icons.text_fields_rounded,
        size: 17,
      ),
      backgroundColor: active ? const Color(0xFFDBEAFE) : Colors.white,
      side: BorderSide(
        color: active
            ? const Color(0xFF2563EB)
            : Colors.black.withValues(alpha: 0.08),
      ),
      onPressed: () => setState(() => _mode = mode),
    );
  }

  Widget _toolbarAction(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      onPressed: onTap,
    );
  }

  Widget _symbolGroup(String label, List<String> symbols) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1E3A8A),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ...symbols.map((symbol) {
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _insert(symbol),
              child: Container(
                height: 34,
                width: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Text(
                  symbol,
                  style: const TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _RegularBatchNotice extends StatelessWidget {
  const _RegularBatchNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.groups_2_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Regular Batch",
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Released tests are available to Regular Batch students automatically.",
                  style: TextStyle(
                    color: Colors.blueGrey.shade700,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

class _ClassTestSection extends StatelessWidget {
  const _ClassTestSection({
    required this.classValue,
    required this.docs,
    required this.buildCard,
  });

  final String classValue;
  final List<QueryDocumentSnapshot> docs;
  final Widget Function(QueryDocumentSnapshot doc) buildCard;

  @override
  Widget build(BuildContext context) {
    final releasedCount = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data["status"]?.toString() == "released";
    }).length;
    final draftCount = docs.length - releasedCount;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: ExpansionTile(
        initiallyExpanded: classValue == "10",
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Container(
          height: 44,
          width: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.school, color: Color(0xFF2563EB)),
        ),
        title: Text(
          AcademicCatalog.classLabel(classValue),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        subtitle: Text(
          "${docs.length} test${docs.length == 1 ? "" : "s"} • "
          "$releasedCount released • $draftCount draft",
        ),
        children: [
          ...docs.map(
            (doc) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: buildCard(doc),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.id,
    required this.data,
    required this.onEdit,
    required this.onReuse,
    required this.onRelease,
    required this.onCancel,
    required this.onDelete,
    required this.onView,
    required this.onReopen,
  });

  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onReuse;
  final VoidCallback onRelease;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onView;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final scheduledAt = data["scheduledAt"] is Timestamp
        ? (data["scheduledAt"] as Timestamp).toDate()
        : DateTime(2000);
    final questions = data["questions"];
    final questionCount = questions is List ? questions.length : 0;
    final status = data["status"]?.toString() == "released"
        ? "released"
        : "draft";
    final canView =
        status == "released" && !DateTime.now().isBefore(scheduledAt);
    final timingMode = data["timingMode"]?.toString() == "totalOnly"
        ? "Total timer"
        : "Per-question timer";
    final location = data["testLocation"]?.toString() == "home"
        ? "At home"
        : "At tuition";
    final targetBatch = AcademicCatalog.mcqTargetBatch(data);
    final released = status == "released";
    final statusColor = released
        ? const Color(0xFF16A34A)
        : const Color(0xFFF97316);
    final statusBg = released
        ? const Color(0xFFECFDF5)
        : const Color(0xFFFFF7ED);
    final classLabel = AcademicCatalog.classLabel(
      AcademicCatalog.mcqTargetClass(data, fallback: ""),
    );
    final dateLabel = DateFormat("dd MMM yyyy").format(scheduledAt);
    final timeLabel = DateFormat("hh:mm a").format(scheduledAt);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        collapsedBackgroundColor: statusBg.withValues(alpha: 0.48),
        backgroundColor: Colors.white,
        tilePadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          height: 46,
          width: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            released ? Icons.cloud_done_rounded : Icons.edit_calendar_rounded,
            color: statusColor,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _McqStatusPill(
              released: released,
              label: released ? "Released" : "Not released",
            ),
            const SizedBox(height: 7),
            Text(
              data["chapterName"]?.toString() ?? "MCQ Test",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _TestInfoPill(icon: Icons.school_outlined, label: classLabel),
              _TestInfoPill(
                icon: Icons.groups_2_outlined,
                label: AcademicCatalog.batchLabel(targetBatch),
              ),
              _TestInfoPill(
                icon: Icons.quiz_outlined,
                label: "$questionCount questions",
              ),
              _TestInfoPill(icon: Icons.event_outlined, label: dateLabel),
              _TestInfoPill(icon: Icons.schedule_outlined, label: timeLabel),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          itemBuilder: (_) => [
            const PopupMenuItem(value: "edit", child: Text("Edit")),
            const PopupMenuItem(
              value: "reuse",
              child: Text("Reuse for another class"),
            ),
            if (canView)
              const PopupMenuItem(value: "view", child: Text("View Test")),
            if (status == "draft")
              const PopupMenuItem(value: "release", child: Text("Release")),
            if (status == "released")
              const PopupMenuItem(
                value: "reopen",
                child: Text("Reopen for student"),
              ),
            if (status == "released")
              const PopupMenuItem(value: "cancel", child: Text("Cancel Test")),
            const PopupMenuItem(value: "delete", child: Text("Delete")),
          ],
          onSelected: (value) {
            if (value == "edit") onEdit();
            if (value == "reuse") onReuse();
            if (value == "view") onView();
            if (value == "release") onRelease();
            if (value == "reopen") onReopen();
            if (value == "cancel") onCancel();
            if (value == "delete") onDelete();
          },
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Icon(
                  released
                      ? Icons.verified_rounded
                      : Icons.pending_actions_rounded,
                  color: statusColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    released
                        ? "Released to students. Private reopen is available from the menu."
                        : "Draft test. Release it when it is ready for students.",
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(label: "Marks", value: "${data["totalMarks"] ?? 0}"),
              _MiniStat(
                label: "+ / Q",
                value: "${data["marksPerQuestion"] ?? 0}",
              ),
              _MiniStat(
                label: "- / Q",
                value: data["negativeMarkingEnabled"] == true
                    ? "${data["negativeMarksPerQuestion"] ?? 0}"
                    : "Off",
              ),
              _MiniStat(
                label: "Time",
                value: "${data["totalTimeMinutes"] ?? 0}m",
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _InlineTestDetail(icon: Icons.timer, label: timingMode),
                _InlineTestDetail(
                  icon: Icons.location_on_outlined,
                  label: location,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: canView
                ? FilledButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text("View Test"),
                  )
                : OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.lock_clock_rounded),
                    label: Text(
                      status == "released"
                          ? "View available after test time"
                          : "Release test to enable viewing",
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _McqStatusPill extends StatelessWidget {
  const _McqStatusPill({required this.released, required this.label});

  final bool released;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = released ? const Color(0xFF16A34A) : const Color(0xFFF97316);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            released ? Icons.done_all_rounded : Icons.lock_clock_rounded,
            size: 14,
            color: color,
          ),
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

class _TestInfoPill extends StatelessWidget {
  const _TestInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineTestDetail extends StatelessWidget {
  const _InlineTestDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF475569)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.64),
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewQuestionCard extends StatelessWidget {
  const _PreviewQuestionCard({
    required this.index,
    required this.question,
    required this.options,
    required this.correctIndex,
  });

  final int index;
  final String question;
  final List<String> options;
  final int correctIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 34,
                width: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${index + 1}",
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  question,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...options.asMap().entries.map((entry) {
            final isCorrect = entry.key == correctIndex;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isCorrect
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCorrect
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCorrect
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: isCorrect
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF94A3B8),
                    size: 18,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: isCorrect
                            ? const Color(0xFF14532D)
                            : const Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PreviewEmptyResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_empty_rounded, color: Color(0xFF64748B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "No student has submitted this test yet.",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewResultTile extends StatelessWidget {
  const _PreviewResultTile({
    required this.rank,
    required this.result,
    required this.totalMarks,
  });

  final int rank;
  final McqComputedResult result;
  final double totalMarks;

  String _format(num value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  String _timeLabel(int seconds) {
    if (seconds >= (1 << 29)) return "--";
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return "${minutes}m ${remainingSeconds.toString().padLeft(2, '0')}s";
  }

  @override
  Widget build(BuildContext context) {
    final rankColor = rank == 1
        ? const Color(0xFFD97706)
        : rank == 2
        ? const Color(0xFF64748B)
        : rank == 3
        ? const Color(0xFFB45309)
        : const Color(0xFF2563EB);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              "#$rank",
              style: TextStyle(color: rankColor, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ResultMetricChip(
                      label: "Correct",
                      value: result.correctCount,
                      color: const Color(0xFF059669),
                    ),
                    _ResultMetricChip(
                      label: "Incorrect",
                      value: result.wrongCount,
                      color: const Color(0xFFDC2626),
                    ),
                    _ResultMetricChip(
                      label: "Skipped",
                      value: result.unansweredCount,
                      color: const Color(0xFF64748B),
                    ),
                    _ResultMetricChip(
                      label: _timeLabel(result.timeTakenSeconds),
                      value: null,
                      color: const Color(0xFF2563EB),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "${_format(result.score)}/${_format(totalMarks)}",
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultMetricChip extends StatelessWidget {
  const _ResultMetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        value == null ? label : "$value $label",
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
