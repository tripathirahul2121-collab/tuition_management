import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  final titleController = TextEditingController();
  final messageController = TextEditingController();

  DateTime? scheduledDateTime;
  String selectedTarget = AcademicCatalog.allClassesTarget;

  @override
  void dispose() {
    titleController.dispose();
    messageController.dispose();
    super.dispose();
  }

  ////////////////////////////////////////////////////////////
  /// STREAM
  ////////////////////////////////////////////////////////////

  Stream<QuerySnapshot> _updatesStream() {
    return FirebaseFirestore.instance
        .collection("updates")
        .orderBy("scheduledAt", descending: true)
        .limit(QueryLimits.recentUpdates)
        .snapshots();
  }

  ////////////////////////////////////////////////////////////
  /// PICK DATE
  ////////////////////////////////////////////////////////////

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (date == null) return;
    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time == null) return;

    setState(() {
      scheduledDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  ////////////////////////////////////////////////////////////
  /// POST UPDATE
  ////////////////////////////////////////////////////////////

  Future<void> _postUpdate() async {
    if (titleController.text.trim().isEmpty ||
        messageController.text.trim().isEmpty) {
      return;
    }

    await FirebaseFirestore.instance.collection("updates").add({
      "title": titleController.text.trim(),
      "message": messageController.text.trim(),
      "target": selectedTarget,
      "targetLabel": AcademicCatalog.classLabel(selectedTarget),
      "scheduledAt": Timestamp.fromDate(scheduledDateTime ?? DateTime.now()),
    });

    titleController.clear();
    messageController.clear();
    scheduledDateTime = null;
    selectedTarget = AcademicCatalog.allClassesTarget;

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Update Scheduled")));

    setState(() {});
  }

  ////////////////////////////////////////////////////////////
  /// DELETE UPDATE
  ////////////////////////////////////////////////////////////

  Future<void> _deleteUpdate(String id, String title) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Announcement?"),
          content: Text(
            title.isEmpty
                ? "This post will be removed."
                : "\"$title\" will be removed.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    await FirebaseFirestore.instance.collection("updates").doc(id).delete();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Announcement deleted")));
  }

  ////////////////////////////////////////////////////////////
  /// FORMAT DATE + TIME
  ////////////////////////////////////////////////////////////

  String formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM • hh:mm a').format(dateTime);
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Announcements"), centerTitle: true),

      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //////////////////////////////////////////////////////
              /// CREATE ANNOUNCEMENT CARD
              //////////////////////////////////////////////////////
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.15),
                      theme.colorScheme.primary.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 20,
                      spreadRadius: -5,
                      offset: const Offset(0, 8),
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    ),
                  ],
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Create Announcement",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: "Title",
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Message",
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      initialValue: selectedTarget,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Class Setting",
                        border: OutlineInputBorder(),
                      ),
                      items: AcademicCatalog.updateTargets.map((target) {
                        return DropdownMenuItem(
                          value: target,
                          child: Text(AcademicCatalog.classLabel(target)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedTarget = value);
                      },
                    ),

                    const SizedBox(height: 12),

                    //////////////////////////////////////////////////////
                    /// DATE TIME PICKER UI
                    //////////////////////////////////////////////////////
                    GestureDetector(
                      onTap: _pickDateTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                scheduledDateTime == null
                                    ? "Select Schedule (Date & Time)"
                                    : formatDateTime(scheduledDateTime!),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _postUpdate,
                        child: const Text(
                          "Post Update",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              //////////////////////////////////////////////////////
              /// HEADER
              //////////////////////////////////////////////////////
              const Text(
                "Recent Updates",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              //////////////////////////////////////////////////////
              /// LIST
              //////////////////////////////////////////////////////
              StreamBuilder<QuerySnapshot>(
                stream: _updatesStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final updates = snapshot.data!.docs;

                  if (updates.isEmpty) {
                    return const Text("No Updates Yet");
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: updates.length,
                    itemBuilder: (_, index) {
                      final update = updates[index];
                      final data = update.data() as Map<String, dynamic>;

                      final DateTime time = (data["scheduledAt"] as Timestamp)
                          .toDate();
                      final title = data["title"]?.toString() ?? "";
                      final target =
                          data["target"]?.toString() ??
                          AcademicCatalog.allClassesTarget;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              color: Colors.black.withValues(alpha: 0.05),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.campaign, color: Colors.blue),

                                const SizedBox(width: 8),

                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                                Text(
                                  formatDateTime(time),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),

                                IconButton(
                                  tooltip: "Delete",
                                  onPressed: () =>
                                      _deleteUpdate(update.id, title),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            Text(
                              data["message"] ?? "",
                              style: const TextStyle(fontSize: 14),
                            ),

                            const SizedBox(height: 10),

                            Chip(
                              avatar: const Icon(Icons.groups, size: 18),
                              label: Text(AcademicCatalog.classLabel(target)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
