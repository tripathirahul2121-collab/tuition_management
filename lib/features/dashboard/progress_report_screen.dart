import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/academic_catalog.dart';

////////////////////////////////////////////////////////////
/// MAIN SCREEN
////////////////////////////////////////////////////////////

class ProgressReportScreen extends StatelessWidget {
  const ProgressReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<List<Color>> gradients = [
      [Color(0xFF667EEA), Color(0xFF764BA2)],
      [Color(0xFF134E5E), Color(0xFF71B280)],
      [Color(0xFF42275A), Color(0xFF734B6D)],
      [Color(0xFF1D2671), Color(0xFFC33764)],
      [Color(0xFF11998E), Color(0xFF38EF7D)],
    ];

    const classes = AcademicCatalog.classValues;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Progress Report",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: classes.length,
        itemBuilder: (context, index) {
          final cls = classes[index];
          final gradient = gradients[index % gradients.length];

          final displayText = AcademicCatalog.classLabel(cls);

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClassProgressScreen(className: cls),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(colors: gradient),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      color: gradient.first.withValues(alpha: 0.35),
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bar_chart_rounded, color: Colors.white),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        displayText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// CLASS SCREEN
////////////////////////////////////////////////////////////

class ClassProgressScreen extends StatefulWidget {
  final String className;

  const ClassProgressScreen({super.key, required this.className});

  @override
  State<ClassProgressScreen> createState() => _ClassProgressScreenState();
}

class _ClassProgressScreenState extends State<ClassProgressScreen> {
  DateTime selectedDate = DateTime.now();
  String selectedSubject = "Maths";
  String selectedBatch = AcademicCatalog.regularBatch;
  static const otherSubjectOption = "Other";

  final totalMarksController = TextEditingController();
  final chapterController = TextEditingController();

  final Map<String, TextEditingController> marksControllers = {};
  final Map<String, bool> absentMap = {};
  final Map<String, String> feedbackMap = {};
  final Map<String, String> feedbackTypeMap = {};
  String get _progressDocId =>
      AcademicCatalog.batchDocId(widget.className, selectedBatch);
  final TextInputFormatter decimalMarksFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
        final text = newValue.text;
        final isValid =
            text.isEmpty || RegExp(r'^\d{0,3}(\.\d{0,2})?$').hasMatch(text);
        return isValid ? newValue : oldValue;
      });

  @override
  void dispose() {
    totalMarksController.dispose();
    chapterController.dispose();
    for (final controller in marksControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  final List<String> positiveTemplates = [
    "Excellent performance. Keep it up!",
    "Very good progress.",
  ];

  final List<String> negativeTemplates = [
    "Needs improvement.",
    "Careless mistakes observed.",
  ];

  Future<Map<String, List<String>>> _loadSavedFeedbackTemplates() async {
    final doc = await FirebaseFirestore.instance
        .collection("feedback_templates")
        .doc(_progressDocId)
        .get();
    final data = doc.data() ?? {};

    List<String> values(String key) {
      final raw = data[key];
      return raw is List
          ? raw
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toList()
          : <String>[];
    }

    return {
      "Positive": {...positiveTemplates, ...values("positive")}.toList(),
      "Negative": {...negativeTemplates, ...values("negative")}.toList(),
    };
  }

  Future<void> _saveFeedbackTemplate(String text, bool isPositive) async {
    final value = text.trim();
    if (value.isEmpty) return;

    await FirebaseFirestore.instance
        .collection("feedback_templates")
        .doc(_progressDocId)
        .set({
          isPositive ? "positive" : "negative": FieldValue.arrayUnion([value]),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _deleteFeedbackTemplate(String text, bool isPositive) async {
    final value = text.trim();
    if (value.isEmpty) return;

    await FirebaseFirestore.instance
        .collection("feedback_templates")
        .doc(_progressDocId)
        .set({
          isPositive ? "positive" : "negative": FieldValue.arrayRemove([value]),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _customSubjectsStream() {
    return AcademicCatalog.customSubjectsStream(widget.className);
  }

  List<String> _subjectsWithCustom(Map<String, dynamic>? data) {
    return AcademicCatalog.subjectsWithCustom(widget.className, data);
  }

  Future<String?> _addSubject() async {
    final controller = TextEditingController();

    final subject = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Subject"),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: "Subject name",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Add"),
          ),
        ],
      ),
    );

    if (subject == null || subject.isEmpty) return null;

    await FirebaseFirestore.instance
        .collection("custom_subjects")
        .doc(_progressDocId)
        .set({
          "subjects": FieldValue.arrayUnion([subject]),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    AcademicCatalog.clearSubjectsCache(widget.className);

    if (!mounted) return null;
    setState(() => selectedSubject = subject);
    return subject;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  void _keepFocusedFieldVisible(BuildContext fieldContext) {
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted || !fieldContext.mounted) return;
      Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    });
  }

  Future<void> _openFeedbackDialog(String id, String name) async {
    final result = await showModalBottomSheet<_FeedbackDialogResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeedbackDialog(
        name: name,
        initialText: feedbackMap[id] ?? "",
        initialType: feedbackTypeMap[id] ?? "Positive",
        fallbackTemplates: {
          "Positive": positiveTemplates,
          "Negative": negativeTemplates,
        },
        templatesFuture: _loadSavedFeedbackTemplates(),
        onLoadTemplates: _loadSavedFeedbackTemplates,
        onSaveTemplate: _saveFeedbackTemplate,
        onDeleteTemplate: _deleteFeedbackTemplate,
      ),
    );

    if (result == null) return;
    setState(() {
      if (result.deleteComment) {
        feedbackMap.remove(id);
        feedbackTypeMap.remove(id);
        return;
      }
      feedbackMap[id] = result.text;
      feedbackTypeMap[id] = result.type;
    });
  }

  ////////////////////////////////////////////////////////////
  /// SAVE
  ////////////////////////////////////////////////////////////

  Future<void> _saveMarks() async {
    final Map<String, dynamic> studentsData = {};

    for (final entry in marksControllers.entries) {
      final marks = entry.value.text.trim();
      final isAbsent = absentMap[entry.key] == true || marks.isEmpty;
      studentsData[entry.key] = {
        "marks": isAbsent ? "" : marks,
        "absent": isAbsent,
        "feedback": feedbackMap[entry.key] ?? "",
        "type": feedbackTypeMap[entry.key] ?? "",
        "feedbackRead": (feedbackMap[entry.key] ?? "").trim().isEmpty,
      };
    }

    await FirebaseFirestore.instance
        .collection("progress")
        .doc(_progressDocId)
        .collection(selectedSubject)
        .doc("${selectedDate.day}-${selectedDate.month}-${selectedDate.year}")
        .set({
          "chapter": chapterController.text.trim(),
          "totalMarks": totalMarksController.text.trim(),
          "students": studentsData,
          "date": selectedDate,
        });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Saved Successfully"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final dateText =
        "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}";

    final classTitle = AcademicCatalog.classLabel(widget.className);
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: AppBar(title: Text(classTitle)),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String>(
              initialValue: selectedBatch,
              decoration: const InputDecoration(labelText: "Batch"),
              items: AcademicCatalog.batchValues.map((value) {
                return DropdownMenuItem(
                  value: value,
                  child: Text(AcademicCatalog.batchLabel(value)),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  selectedBatch = AcademicCatalog.normalizeBatch(value);
                  marksControllers.clear();
                  absentMap.clear();
                  feedbackMap.clear();
                  feedbackTypeMap.clear();
                });
              },
            ),
          ),

          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade50, Colors.white],
                  ),
                  boxShadow: const [
                    BoxShadow(blurRadius: 12, color: Colors.black12),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.assignment_turned_in,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Test Update",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (fieldContext) {
                        return TextField(
                          controller: totalMarksController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onTap: () => _keepFocusedFieldVisible(fieldContext),
                          inputFormatters: [decimalMarksFormatter],
                          decoration: const InputDecoration(
                            labelText: "Total Marks",
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _customSubjectsStream(),
                      builder: (context, snapshot) {
                        final subjects = _subjectsWithCustom(
                          snapshot.data?.data(),
                        );
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

                        return Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey("progress-subject-$value"),
                                isExpanded: true,
                                initialValue: value,
                                decoration: const InputDecoration(
                                  labelText: "Subject",
                                ),
                                items: [
                                  ...subjects.map((sub) {
                                    return DropdownMenuItem(
                                      value: sub,
                                      child: Text(
                                        sub,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                  const DropdownMenuItem(
                                    value: otherSubjectOption,
                                    child: Text("Other"),
                                  ),
                                ],
                                onChanged: (val) async {
                                  if (val == null) return;
                                  if (val == otherSubjectOption) {
                                    await _addSubject();
                                    return;
                                  }
                                  setState(() => selectedSubject = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filledTonal(
                              tooltip: "Add subject",
                              onPressed: _addSubject,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: chapterController,
                      decoration: const InputDecoration(
                        labelText: "Chapter / Topic",
                      ),
                    ),

                    const SizedBox(height: 14),

                    InkWell(
                      onTap: _pickDate,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_month),
                          const SizedBox(width: 8),
                          Text("Test Date: $dateText"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          //////////////////////////////////////////////////////
          /// STUDENT LIST
          //////////////////////////////////////////////////////
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("users")
                  .where("role", isEqualTo: "student")
                  .where("class", isEqualTo: widget.className)
                  .orderBy("name")
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final students =
                    snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data["active"] != false &&
                          AcademicCatalog.batchMatches(data, selectedBatch);
                    }).toList()..sort(
                      (a, b) => (a["name"] ?? "").toString().compareTo(
                        (b["name"] ?? "").toString(),
                      ),
                    );

                return ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 110,
                  ),
                  itemCount: students.length,
                  itemBuilder: (_, index) {
                    final doc = students[index];
                    final name = doc["name"] ?? "Unnamed";

                    marksControllers.putIfAbsent(
                      doc.id,
                      () => TextEditingController(),
                    );
                    absentMap.putIfAbsent(doc.id, () => false);
                    final isAbsent = absentMap[doc.id] == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                            color: Colors.black.withValues(alpha: 0.04),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.10),
                            child: Text(
                              "${index + 1}",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 86,
                            child: Builder(
                              builder: (fieldContext) {
                                return TextField(
                                  controller: marksControllers[doc.id],
                                  enabled: !isAbsent,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onTap: () =>
                                      _keepFocusedFieldVisible(fieldContext),
                                  onChanged: (value) {
                                    if (value.trim().isNotEmpty &&
                                        absentMap[doc.id] == true) {
                                      setState(() {
                                        absentMap[doc.id] = false;
                                      });
                                    }
                                  },
                                  inputFormatters: [decimalMarksFormatter],
                                  textAlign: TextAlign.center,
                                  scrollPadding: EdgeInsets.only(
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).viewInsets.bottom +
                                        260,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: isAbsent ? "Ab" : "Marks",
                                    filled: true,
                                    fillColor: isAbsent
                                        ? Colors.red.shade50
                                        : const Color(0xFFF8FAFC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          FilterChip(
                            label: const Text("Ab"),
                            selected: isAbsent,
                            onSelected: (selected) {
                              setState(() {
                                absentMap[doc.id] = selected;
                                if (selected) {
                                  marksControllers[doc.id]?.clear();
                                }
                              });
                            },
                          ),
                          IconButton.filledTonal(
                            tooltip: "Comment on marks",
                            icon: Icon(
                              feedbackMap[doc.id] != null
                                  ? Icons.check_circle
                                  : Icons.feedback_outlined,
                              color: feedbackMap[doc.id] != null
                                  ? Colors.green
                                  : const Color(0xFF64748B),
                            ),
                            onPressed: () => _openFeedbackDialog(doc.id, name),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          if (!keyboardOpen)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveMarks,
                  child: const Text(
                    "Save Marks & Feedback",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackDialogResult {
  const _FeedbackDialogResult({
    required this.text,
    required this.type,
    this.deleteComment = false,
  });

  final String text;
  final String type;
  final bool deleteComment;
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({
    required this.name,
    required this.initialText,
    required this.initialType,
    required this.fallbackTemplates,
    required this.templatesFuture,
    required this.onLoadTemplates,
    required this.onSaveTemplate,
    required this.onDeleteTemplate,
  });

  final String name;
  final String initialText;
  final String initialType;
  final Map<String, List<String>> fallbackTemplates;
  final Future<Map<String, List<String>>> templatesFuture;
  final Future<Map<String, List<String>>> Function() onLoadTemplates;
  final Future<void> Function(String text, bool isPositive) onSaveTemplate;
  final Future<void> Function(String text, bool isPositive) onDeleteTemplate;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  late final TextEditingController _controller;
  late Future<Map<String, List<String>>> _templatesFuture;
  late bool _isPositive;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _templatesFuture = widget.templatesFuture;
    _isPositive = widget.initialType != "Negative";
    _hasText = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText == _hasText || !mounted) return;
    setState(() => _hasText = hasText);
  }

  Future<void> _saveCurrentTemplate() async {
    await widget.onSaveTemplate(_controller.text, _isPositive);
    if (!mounted) return;
    setState(() {
      _templatesFuture = _reloadTemplates();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Template added to collection")),
    );
  }

  Future<Map<String, List<String>>> _reloadTemplates() async {
    final saved = await widget.onLoadTemplates();
    return {
      "Positive": {
        ...(widget.fallbackTemplates["Positive"] ?? const <String>[]),
        ...(saved["Positive"] ?? const <String>[]),
      }.toList(),
      "Negative": {
        ...(widget.fallbackTemplates["Negative"] ?? const <String>[]),
        ...(saved["Negative"] ?? const <String>[]),
      }.toList(),
    };
  }

  Future<void> _openTemplateLibrary() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplateLibrarySheet(
        fallbackTemplates: widget.fallbackTemplates,
        templatesFuture: _templatesFuture,
        onLoadTemplates: widget.onLoadTemplates,
        onSaveTemplate: widget.onSaveTemplate,
        onDeleteTemplate: widget.onDeleteTemplate,
      ),
    );
    if (!mounted) return;
    setState(() {
      _templatesFuture = _reloadTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
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
              children: [
                Row(
                  children: [
                    const Icon(Icons.mode_comment_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Comment for ${widget.name}",
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (_hasText)
                      IconButton.filledTonal(
                        tooltip: "Delete attached comment",
                        onPressed: () {
                          Navigator.pop(
                            context,
                            const _FeedbackDialogResult(
                              text: "",
                              type: "",
                              deleteComment: true,
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.grey.shade200,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isPositive = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: _isPositive
                                  ? Colors.green
                                  : Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Positive",
                              style: TextStyle(
                                color: _isPositive
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isPositive = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: !_isPositive
                                  ? Colors.red
                                  : Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Negative",
                              style: TextStyle(
                                color: !_isPositive
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<Map<String, List<String>>>(
                  future: _templatesFuture,
                  builder: (context, snapshot) {
                    final templatesByType =
                        snapshot.data ?? widget.fallbackTemplates;
                    final templates =
                        templatesByType[_isPositive
                            ? "Positive"
                            : "Negative"] ??
                        const <String>[];

                    return DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText:
                            snapshot.connectionState == ConnectionState.waiting
                            ? "Templates loading..."
                            : "Ready templates",
                      ),
                      items: templates.map((template) {
                        return DropdownMenuItem(
                          value: template,
                          child: Text(
                            template,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) _controller.text = value;
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _openTemplateLibrary,
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text("Template Library"),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: "Add custom feedback",
                    hintText: "Write comment over marks scored",
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !_hasText ? null : _saveCurrentTemplate,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text("Add Template"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            _FeedbackDialogResult(
                              text: _controller.text.trim(),
                              type: _isPositive ? "Positive" : "Negative",
                            ),
                          );
                        },
                        icon: const Icon(Icons.check),
                        label: const Text("Attach"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateLibrarySheet extends StatefulWidget {
  const _TemplateLibrarySheet({
    required this.fallbackTemplates,
    required this.templatesFuture,
    required this.onLoadTemplates,
    required this.onSaveTemplate,
    required this.onDeleteTemplate,
  });

  final Map<String, List<String>> fallbackTemplates;
  final Future<Map<String, List<String>>> templatesFuture;
  final Future<Map<String, List<String>>> Function() onLoadTemplates;
  final Future<void> Function(String text, bool isPositive) onSaveTemplate;
  final Future<void> Function(String text, bool isPositive) onDeleteTemplate;

  @override
  State<_TemplateLibrarySheet> createState() => _TemplateLibrarySheetState();
}

class _TemplateLibrarySheetState extends State<_TemplateLibrarySheet> {
  late Future<Map<String, List<String>>> _templatesFuture;
  final _newTemplateController = TextEditingController();
  bool _isPositive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _templatesFuture = widget.templatesFuture;
  }

  @override
  void dispose() {
    _newTemplateController.dispose();
    super.dispose();
  }

  Future<Map<String, List<String>>> _reloadTemplates() async {
    final saved = await widget.onLoadTemplates();
    return {
      "Positive": {
        ...(widget.fallbackTemplates["Positive"] ?? const <String>[]),
        ...(saved["Positive"] ?? const <String>[]),
      }.toList(),
      "Negative": {
        ...(widget.fallbackTemplates["Negative"] ?? const <String>[]),
        ...(saved["Negative"] ?? const <String>[]),
      }.toList(),
    };
  }

  Future<void> _addTemplate() async {
    final text = _newTemplateController.text.trim();
    if (text.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      await widget.onSaveTemplate(text, _isPositive);
      _newTemplateController.clear();
      if (!mounted) return;
      setState(() {
        _templatesFuture = _reloadTemplates();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Template added")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteTemplate(String template) async {
    await widget.onDeleteTemplate(template, _isPositive);
    if (!mounted) return;
    setState(() {
      _templatesFuture = _reloadTemplates();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Template removed")));
  }

  @override
  Widget build(BuildContext context) {
    final type = _isPositive ? "Positive" : "Negative";
    final fallbackForType = widget.fallbackTemplates[type] ?? const <String>[];

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
                Row(
                  children: [
                    const Icon(Icons.library_books_outlined),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Template Library",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.grey.shade200,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isPositive = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: _isPositive
                                  ? Colors.green
                                  : Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Positive",
                              style: TextStyle(
                                color: _isPositive
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isPositive = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: !_isPositive
                                  ? Colors.red
                                  : Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Negative",
                              style: TextStyle(
                                color: !_isPositive
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTemplateController,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: "Add $type template",
                          hintText: "Write a reusable feedback line",
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _saving ? null : _addTemplate,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<Map<String, List<String>>>(
                  future: _templatesFuture,
                  builder: (context, snapshot) {
                    final templatesByType =
                        snapshot.data ?? widget.fallbackTemplates;
                    final templates = templatesByType[type] ?? const <String>[];

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (templates.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text("No templates added yet."),
                      );
                    }

                    return Column(
                      children: templates.map((template) {
                        final isDefaultTemplate = fallbackForType.contains(
                          template,
                        );
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  template,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isDefaultTemplate)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Text(
                                    "Default",
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                IconButton(
                                  tooltip: "Delete template",
                                  onPressed: () => _deleteTemplate(template),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
