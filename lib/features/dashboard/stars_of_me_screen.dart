// 🔥 ONLY IMPORTANT CHANGES FILE — CLEAN + ELITE UI

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';
import 'mcq_result_utils.dart';

enum _StarsView { board, tuition }

class StarsOfMEScreen extends StatefulWidget {
  final bool readOnly;

  const StarsOfMEScreen({super.key, this.readOnly = false});

  @override
  State<StarsOfMEScreen> createState() => _StarsOfMEScreenState();
}

class _StarsOfMEScreenState extends State<StarsOfMEScreen> {
  final nameController = TextEditingController();
  final schoolController = TextEditingController();
  final classController = TextEditingController();
  final sessionController = TextEditingController();
  final List<_SubjectScoreInput> subjectScores = [_SubjectScoreInput()];

  XFile? imageFile;
  bool isLoading = false;
  _StarsView _starsView = _StarsView.board;

  @override
  void dispose() {
    nameController.dispose();
    schoolController.dispose();
    classController.dispose();
    sessionController.dispose();
    for (final score in subjectScores) {
      score.dispose();
    }
    super.dispose();
  }

  ////////////////////////////////////////////////////////////
  /// IMAGE PICK / CHANGE
  ////////////////////////////////////////////////////////////

  Future<void> pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() => imageFile = picked);
    }
  }

  void showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text("Change Photo"),
            onTap: () {
              Navigator.pop(context);
              pickImage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Remove Photo"),
            onTap: () {
              Navigator.pop(context);
              setState(() => imageFile = null);
            },
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// UPLOAD
  ////////////////////////////////////////////////////////////

  Future<String?> uploadImage(XFile file) async {
    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();

      final ref = FirebaseStorage.instance.ref().child(
        "stars/${sessionController.text}/$fileName.jpg",
      );

      final snapshot = await ref.putData(
        await file.readAsBytes(),
        SettableMetadata(contentType: file.mimeType ?? 'image/jpeg'),
      );
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      _snack("Upload failed");
      return null;
    }
  }

  ////////////////////////////////////////////////////////////
  /// SAVE
  ////////////////////////////////////////////////////////////

  Future<void> saveData() async {
    if (nameController.text.isEmpty ||
        classController.text.isEmpty ||
        sessionController.text.isEmpty) {
      _snack("Fill all fields");
      return;
    }

    final scores = subjectScores
        .map((score) => score.toData())
        .where((score) => score != null)
        .cast<Map<String, dynamic>>()
        .toList();

    Navigator.pop(context);

    _snack("Star added ⭐");

    String? url;
    if (imageFile != null) {
      url = await uploadImage(imageFile!);
    }

    await FirebaseFirestore.instance.collection("stars").add({
      "name": nameController.text.trim(),
      "school": schoolController.text.trim(),
      "class": classController.text.trim(),
      "session": sessionController.text.trim(),
      "subjectScores": scores,
      "image": url,
      "createdAt": Timestamp.now(),
    });
  }

  ////////////////////////////////////////////////////////////
  /// DELETE (IMPROVED UI)
  ////////////////////////////////////////////////////////////

  void showDeleteDialog(String id, String? imageUrl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Student"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              await FirebaseFirestore.instance
                  .collection("stars")
                  .doc(id)
                  .delete();

              if (imageUrl != null) {
                await FirebaseStorage.instance.refFromURL(imageUrl).delete();
              }

              _snack("Deleted");
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDetailsDialog(String id, Map data) async {
    final editNameController = TextEditingController(
      text: data["name"]?.toString() ?? "",
    );
    final editSchoolController = TextEditingController(
      text: data["school"]?.toString() ?? "",
    );
    final editClassController = TextEditingController(
      text: data["class"]?.toString() ?? "",
    );
    final editSessionController = TextEditingController(
      text: data["session"]?.toString() ?? "",
    );

    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final availableHeight =
            MediaQuery.of(context).size.height -
            MediaQuery.of(context).viewInsets.bottom -
            MediaQuery.of(context).padding.top -
            24;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: availableHeight),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    const Text(
                      "Edit Star Details",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _field(editNameController, "Student Name"),
                    const SizedBox(height: 10),
                    _field(editSchoolController, "School Name"),
                    const SizedBox(height: 10),
                    _field(editClassController, "Class"),
                    const SizedBox(height: 10),
                    _field(editSessionController, "Session"),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.save),
                        label: const Text("Save Details"),
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

    if (shouldSave == true) {
      await FirebaseFirestore.instance.collection("stars").doc(id).update({
        "name": editNameController.text.trim(),
        "school": editSchoolController.text.trim(),
        "class": editClassController.text.trim(),
        "session": editSessionController.text.trim(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _snack("Star details updated");
    }

    editNameController.dispose();
    editSchoolController.dispose();
    editClassController.dispose();
    editSessionController.dispose();
  }

  ////////////////////////////////////////////////////////////
  /// CARD (ELITE UI)
  ////////////////////////////////////////////////////////////

  double _bestScore(Map data) {
    final scores = _subjectScoresFrom(data);
    double best = -1;

    for (final score in scores) {
      final marks = double.tryParse(score["marks"]?.toString() ?? "");
      if (marks != null && marks > best) best = marks;
    }

    return best;
  }

  Widget buildCard(Map data, String id, {bool isTopper = false, int? rank}) {
    final image = data["image"];
    final scores = _subjectScoresFrom(data);
    final name = data["name"]?.toString() ?? "";
    final school = data["school"]?.toString().trim() ?? "";
    final className = data["class"]?.toString() ?? "";
    final session = data["session"]?.toString() ?? "";

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            children: [
              Expanded(
                flex: 7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTapDown: (_) => _precacheStarImage(image),
                      onTap: () => _showPhotoPreview(image),
                      child: _starPhoto(image),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.26),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.08),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    if (!widget.readOnly)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: PopupMenuButton(
                          color: Colors.white,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              child: const Text("Edit Details"),
                              onTap: () => Future.delayed(
                                Duration.zero,
                                () => _showEditDetailsDialog(id, data),
                              ),
                            ),
                            PopupMenuItem(
                              child: const Text("Change Photo"),
                              onTap: () async {
                                final picked = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                );

                                if (picked != null) {
                                  final fileName = DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString();

                                  final ref = FirebaseStorage.instance
                                      .ref()
                                      .child(
                                        "stars/${data["session"]}/$fileName.jpg",
                                      );

                                  final snapshot = await ref.putData(
                                    await picked.readAsBytes(),
                                    SettableMetadata(
                                      contentType:
                                          picked.mimeType ?? 'image/jpeg',
                                    ),
                                  );
                                  final url = await snapshot.ref
                                      .getDownloadURL();

                                  await FirebaseFirestore.instance
                                      .collection("stars")
                                      .doc(id)
                                      .update({"image": url});
                                }
                              },
                            ),
                            PopupMenuItem(
                              child: const Text("Delete"),
                              onTap: () => Future.delayed(
                                Duration.zero,
                                () => showDeleteDialog(id, image),
                              ),
                            ),
                          ],
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (isTopper || rank != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isTopper
                                ? const Color(0xFFFFC857)
                                : Colors.black.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isTopper ? Icons.workspace_premium : Icons.star,
                                color: isTopper ? Colors.black : Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isTopper ? "Topper" : "#$rank",
                                style: TextStyle(
                                  color: isTopper ? Colors.black : Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (className.isNotEmpty) "Class $className",
                          if (school.isNotEmpty) school,
                          if (session.isNotEmpty) session,
                        ].join(" • "),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (scores.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 26,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: scores.take(3).length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              final score = scores[index];
                              return _scoreChip(score);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _starPhoto(dynamic image) {
    final imageUrl = image?.toString().trim();

    if (imageUrl == null || imageUrl.isEmpty) {
      return _photoPlaceholder();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (constraints.maxWidth * pixelRatio).round();
        final cacheHeight = (constraints.maxHeight * pixelRatio).round();

        return Container(
          color: const Color(0xFF111827),
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            cacheWidth: cacheWidth > 0 ? cacheWidth : null,
            cacheHeight: cacheHeight > 0 ? cacheHeight : null,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFC857),
                ),
              );
            },
            errorBuilder: (_, _, _) => _photoPlaceholder(),
          ),
        );
      },
    );
  }

  Widget _previewPhoto(String imageUrl) {
    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFFC857),
          ),
        );
      },
      errorBuilder: (_, _, _) => _photoPlaceholder(),
    );
  }

  void _precacheStarImage(dynamic image) {
    final imageUrl = image?.toString().trim();
    if (imageUrl == null || imageUrl.isEmpty) return;

    precacheImage(NetworkImage(imageUrl), context, onError: (_, _) {});
  }

  void _showPhotoPreview(dynamic image) {
    final imageUrl = image?.toString().trim();
    if (imageUrl == null || imageUrl.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: _previewPhoto(imageUrl),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton.filled(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF475569)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.workspace_premium, color: Colors.white70, size: 54),
      ),
    );
  }

  Widget _scoreChip(Map<String, dynamic> score) {
    final marks = score["marks"]?.toString().trim() ?? "";
    final subject = score["subject"]?.toString().trim() ?? "";
    final text = marks.isEmpty ? subject : "$subject: $marks";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFD37A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8A5A00),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _subjectScoresFrom(Map data) {
    final raw = data["subjectScores"];
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((score) => Map<String, dynamic>.from(score))
        .where(
          (score) => (score["subject"]?.toString().trim() ?? "").isNotEmpty,
        )
        .toList();
  }

  ////////////////////////////////////////////////////////////
  /// FORM
  ////////////////////////////////////////////////////////////

  Widget buildForm([StateSetter? sheetSetState]) {
    final availableHeight =
        MediaQuery.of(context).size.height -
        MediaQuery.of(context).viewInsets.bottom -
        MediaQuery.of(context).padding.top -
        24;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: ListView(
            shrinkWrap: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    /// IMAGE PICK
                    GestureDetector(
                      onTap: () {
                        if (imageFile == null) {
                          pickImage();
                        } else {
                          showImageOptions();
                        }
                      },
                      child: Container(
                        height: 140,
                        width: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.grey.shade200,
                        ),
                        child: imageFile == null
                            ? const Icon(Icons.add_a_photo, size: 40)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: _SelectedImagePreview(file: imageFile!),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    _field(nameController, "Student Name"),
                    const SizedBox(height: 10),
                    _field(schoolController, "School Name"),
                    const SizedBox(height: 10),
                    _field(classController, "Class"),
                    const SizedBox(height: 10),
                    _field(sessionController, "Session"),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Subject scores",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            void update() {
                              subjectScores.add(_SubjectScoreInput());
                            }

                            if (sheetSetState == null) {
                              setState(update);
                            } else {
                              sheetSetState(update);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text("Add Subject"),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    ...subjectScores.asMap().entries.map((entry) {
                      final index = entry.key;
                      final score = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: _field(score.subjectController, "Subject"),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: _field(score.marksController, "Marks"),
                            ),
                            if (subjectScores.length > 1)
                              IconButton(
                                onPressed: () {
                                  void update() {
                                    subjectScores.removeAt(index).dispose();
                                  }

                                  if (sheetSetState == null) {
                                    setState(update);
                                  } else {
                                    sheetSetState(update);
                                  }
                                },
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: saveData,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text("Save Star"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// MAIN UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Stars of ME")),

      floatingActionButton: widget.readOnly || _starsView != _StarsView.board
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                nameController.clear();
                schoolController.clear();
                classController.clear();
                sessionController.clear();
                for (final score in subjectScores) {
                  score.dispose();
                }
                subjectScores
                  ..clear()
                  ..add(_SubjectScoreInput());
                imageFile = null;

                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) {
                    return StatefulBuilder(
                      builder: (context, setSheetState) {
                        return buildForm(setSheetState);
                      },
                    );
                  },
                );
              },
              label: const Text("Add Star"),
              icon: const Icon(Icons.add),
            ),

      body: Column(
        children: [
          _StarsViewSwitcher(
            value: _starsView,
            onChanged: (value) => setState(() => _starsView = value),
          ),
          Expanded(
            child: _starsView == _StarsView.board
                ? _buildBoardToppersBody()
                : const _TuitionToppersPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardToppersBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("stars")
          .orderBy("createdAt", descending: true)
          .limit(QueryLimits.stars)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text("No Stars Yet"));
        }

        if (widget.readOnly) {
          final sortedDocs = docs.toList()
            ..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final scoreCompare = _bestScore(
                bData,
              ).compareTo(_bestScore(aData));
              if (scoreCompare != 0) return scoreCompare;

              final aCreated = aData["createdAt"];
              final bCreated = bData["createdAt"];
              final aDate = aCreated is Timestamp
                  ? aCreated.toDate()
                  : DateTime(2000);
              final bDate = bCreated is Timestamp
                  ? bCreated.toDate()
                  : DateTime(2000);
              return bDate.compareTo(aDate);
            });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDocs.length,
            itemBuilder: (_, i) {
              final doc = sortedDocs[i];
              return Container(
                height: 380,
                margin: const EdgeInsets.only(bottom: 18),
                child: buildCard(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                  isTopper: i == 0,
                  rank: i + 1,
                ),
              );
            },
          );
        }

        final grouped = <String, List<QueryDocumentSnapshot>>{};

        for (var d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final session = data["session"] ?? "Unknown";
          grouped.putIfAbsent(session, () => []).add(d);
        }

        final sessions = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          itemBuilder: (_, i) {
            final session = sessions[i];
            final students = grouped[session]!;

            students.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final scoreCompare = _bestScore(
                bData,
              ).compareTo(_bestScore(aData));
              if (scoreCompare != 0) return scoreCompare;
              final aClass = int.tryParse((a["class"] ?? "0").toString()) ?? 0;
              final bClass = int.tryParse((b["class"] ?? "0").toString()) ?? 0;
              return aClass.compareTo(bClass);
            });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          session,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        "${students.length} stars",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: students.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemBuilder: (_, j) {
                    final doc = students[j];
                    return buildCard(
                      doc.data() as Map<String, dynamic>,
                      doc.id,
                      isTopper: j == 0,
                      rank: j + 1,
                    );
                  },
                ),
                const SizedBox(height: 25),
              ],
            );
          },
        );
      },
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _StarsViewSwitcher extends StatelessWidget {
  const _StarsViewSwitcher({required this.value, required this.onChanged});

  final _StarsView value;
  final ValueChanged<_StarsView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SegmentedButton<_StarsView>(
        segments: const [
          ButtonSegment(
            value: _StarsView.board,
            icon: Icon(Icons.workspace_premium),
            label: Text("Board Toppers"),
          ),
          ButtonSegment(
            value: _StarsView.tuition,
            icon: Icon(Icons.auto_awesome),
            label: Text("Tuition Toppers"),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
            Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _TuitionToppersPanel extends StatefulWidget {
  const _TuitionToppersPanel();

  @override
  State<_TuitionToppersPanel> createState() => _TuitionToppersPanelState();
}

class _TuitionToppersPanelState extends State<_TuitionToppersPanel> {
  late Future<List<TuitionTopperEntry>> _toppersFuture;

  @override
  void initState() {
    super.initState();
    _toppersFuture = loadTuitionToppers();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TuitionTopperEntry>>(
      future: _toppersFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                "Tuition toppers could not load\n${snapshot.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final toppers = snapshot.data!;
        if (toppers.isEmpty) {
          return const Center(child: Text("No tuition toppers yet"));
        }

        final grouped = _groupTuitionToppersByClass(toppers);
        final classValues = grouped.keys.toList()
          ..sort(_compareTuitionTopperClasses);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            _TuitionToppersHero(count: toppers.length),
            const SizedBox(height: 12),
            ...classValues.map(
              (className) => _TuitionTopperClassSection(
                className: className,
                toppers: grouped[className]!,
              ),
            ),
          ],
        );
      },
    );
  }
}

Map<String, List<TuitionTopperEntry>> _groupTuitionToppersByClass(
  List<TuitionTopperEntry> toppers,
) {
  final grouped = <String, List<TuitionTopperEntry>>{};
  for (final topper in toppers) {
    grouped.putIfAbsent(topper.className, () => []).add(topper);
  }

  for (final classToppers in grouped.values) {
    classToppers.sort(compareTuitionTopperEntries);
  }

  return grouped;
}

int _compareTuitionTopperClasses(String a, String b) {
  final aClass = int.tryParse(a) ?? 999;
  final bClass = int.tryParse(b) ?? 999;
  final classCompare = aClass.compareTo(bClass);
  if (classCompare != 0) return classCompare;
  return a.compareTo(b);
}

class _TuitionToppersHero extends StatelessWidget {
  const _TuitionToppersHero({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 22,
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
            child: const Icon(Icons.emoji_events, color: Color(0xFFFFC857)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tuition Toppers",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$count students ranked by topper count, then percentage",
                  style: const TextStyle(
                    color: Color(0xFFCFE0E4),
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

class _TuitionTopperClassSection extends StatelessWidget {
  const _TuitionTopperClassSection({
    required this.className,
    required this.toppers,
  });

  final String className;
  final List<TuitionTopperEntry> toppers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
            child: Row(
              children: [
                Container(
                  height: 34,
                  width: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.school_outlined,
                    size: 19,
                    color: Color(0xFF0369A1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AcademicCatalog.classLabel(className),
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  "${toppers.length} topper${toppers.length == 1 ? "" : "s"}",
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          ...toppers.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TuitionTopperTile(
                rank: entry.key + 1,
                topper: entry.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TuitionTopperTile extends StatelessWidget {
  const _TuitionTopperTile({required this.rank, required this.topper});

  final int rank;
  final TuitionTopperEntry topper;

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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rank <= 3 ? rankColor.withValues(alpha: 0.07) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: rankColor.withValues(alpha: 0.14),
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
                  topper.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "${AcademicCatalog.classLabel(topper.className)} • Latest: ${topper.latestChapter}",
                  maxLines: 1,
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
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${_formatStarNumber(topper.averageTopPercentage)}%",
                style: const TextStyle(
                  color: Color(0xFF0F766E),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                "${topper.toppedCount} top${topper.toppedCount == 1 ? "" : "s"}",
                style: const TextStyle(
                  color: Color(0xFF92400E),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatStarNumber(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

class _SelectedImagePreview extends StatelessWidget {
  const _SelectedImagePreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return Image.memory(snapshot.data!, fit: BoxFit.contain);
      },
    );
  }
}

class _SubjectScoreInput {
  final subjectController = TextEditingController();
  final marksController = TextEditingController();

  Map<String, dynamic>? toData() {
    final subject = subjectController.text.trim();
    final marks = marksController.text.trim();

    if (subject.isEmpty && marks.isEmpty) return null;
    if (subject.isEmpty) return null;

    return {"subject": subject, "marks": marks};
  }

  void dispose() {
    subjectController.dispose();
    marksController.dispose();
  }
}
