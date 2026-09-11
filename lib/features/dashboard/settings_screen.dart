import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/config/app_branding.dart';
import 'admin_dashboard_preferences.dart';
import '../auth/presentation/auth_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;
  String _busyMessage = "";
  String _sourceClass = "6";
  String _targetClass = "7";

  Future<int> _deleteCollection(
    Query<Map<String, dynamic>> query, {
    int pageSize = 450,
  }) async {
    var deleted = 0;

    while (true) {
      final snap = await query.limit(pageSize).get();
      if (snap.docs.isEmpty) return deleted;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }
  }

  Future<void> _resetAcademicSession() async {
    final confirmed = await _confirmTypedAction(
      title: "Reset session data?",
      message:
          "This deletes attendance, progress/report-card tests, teacher remarks, MCQ tests, MCQ templates, MCQ results, and MCQ release notifications. Students, passwords, fees, stars, and normal updates stay safe.",
      expectedText: "RESET",
      actionLabel: "Reset Session",
    );
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _busyMessage = "Clearing MCQ tests...";
    });

    try {
      final firestore = FirebaseFirestore.instance;
      var deletedItems = 0;

      final mcqSnap = await firestore.collection("mcq_tests").get();
      for (final testDoc in mcqSnap.docs) {
        deletedItems += await _deleteCollection(
          testDoc.reference.collection("results"),
        );
      }
      deletedItems += await _deleteCollection(
        firestore.collection("mcq_tests"),
      );

      setState(() => _busyMessage = "Clearing saved MCQ templates...");
      deletedItems += await _deleteCollection(
        firestore.collection("mcq_test_templates"),
      );

      setState(() => _busyMessage = "Clearing MCQ notifications...");
      deletedItems += await _deleteCollection(
        firestore.collection("updates").where("type", isEqualTo: "mcq_test"),
      );

      setState(() => _busyMessage = "Clearing attendance records...");
      for (final className in AcademicCatalog.classValues) {
        for (final batchName in AcademicCatalog.batchValues) {
          final attendanceDoc = firestore
              .collection("attendance")
              .doc(AcademicCatalog.batchDocId(className, batchName));
          deletedItems += await _deleteCollection(
            attendanceDoc.collection("records"),
          );
          await attendanceDoc.delete();
          deletedItems++;
        }
      }

      setState(() => _busyMessage = "Clearing progress/report-card tests...");
      for (final className in AcademicCatalog.classValues) {
        final subjects = await AcademicCatalog.loadSubjectsForClass(className);
        for (final batchName in AcademicCatalog.batchValues) {
          final progressDoc = firestore
              .collection("progress")
              .doc(AcademicCatalog.batchDocId(className, batchName));
          for (final subject in subjects) {
            deletedItems += await _deleteCollection(
              progressDoc.collection(subject),
            );
          }
          await progressDoc.delete();
          deletedItems++;
        }
      }

      setState(() => _busyMessage = "Clearing teacher remarks...");
      deletedItems += await _deleteCollection(
        firestore.collection("teacher_remarks"),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session reset complete ($deletedItems items)")),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Reset failed: $error")));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = "";
        });
      }
    }
  }

  Future<int> _countStudentsForShift({
    String? sourceClass,
    bool promoteAll = false,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final usersSnap = await firestore
        .collection("users")
        .where("role", isEqualTo: "student")
        .get();
    final pendingSnap = await firestore
        .collection("pending_users")
        .where("role", isEqualTo: "student")
        .get();

    bool matches(Map<String, dynamic> data) {
      final cls = data["class"]?.toString() ?? "";
      if (promoteAll) {
        return _nextClass(cls) != null && data["active"] != false;
      }
      return cls == sourceClass && data["active"] != false;
    }

    return usersSnap.docs.where((doc) => matches(doc.data())).length +
        pendingSnap.docs.where((doc) => matches(doc.data())).length;
  }

  Future<void> _shiftStudents({
    required bool promoteAll,
    String? sourceClass,
    String? targetClass,
  }) async {
    final count = await _countStudentsForShift(
      sourceClass: sourceClass,
      promoteAll: promoteAll,
    );
    if (!mounted) return;

    final label = promoteAll
        ? "promote every active student to the next class"
        : "shift $count student record${count == 1 ? "" : "s"} from ${AcademicCatalog.classLabel(sourceClass!)} to ${AcademicCatalog.classLabel(targetClass!)}";
    final confirmed = await _confirmTypedAction(
      title: "Shift students?",
      message:
          "This will $label. Pending generated student passwords are updated too, so future signups stay aligned.",
      expectedText: "SHIFT",
      actionLabel: "Shift Students",
    );
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _busyMessage = "Shifting students...";
    });

    try {
      final updated =
          await _shiftCollectionStudents(
            "users",
            promoteAll: promoteAll,
            sourceClass: sourceClass,
            targetClass: targetClass,
            activeOnly: true,
          ) +
          await _shiftCollectionStudents(
            "pending_users",
            promoteAll: promoteAll,
            sourceClass: sourceClass,
            targetClass: targetClass,
            activeOnly: false,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Class shift complete ($updated records)")),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Class shift failed: $error")));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = "";
        });
      }
    }
  }

  Future<int> _shiftCollectionStudents(
    String collection, {
    required bool promoteAll,
    String? sourceClass,
    String? targetClass,
    required bool activeOnly,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .where("role", isEqualTo: "student")
        .get();
    var batch = FirebaseFirestore.instance.batch();
    var writes = 0;
    var updated = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (writes == 0 || (!force && writes < 450)) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      writes = 0;
    }

    for (final doc in snap.docs) {
      final data = doc.data();
      if (activeOnly && data["active"] == false) continue;
      final currentClass = data["class"]?.toString() ?? "";
      final newClass = promoteAll ? _nextClass(currentClass) : targetClass;
      if (newClass == null || newClass.isEmpty) continue;
      if (!promoteAll && currentClass != sourceClass) continue;

      batch.set(doc.reference, {
        "class": newClass,
        "previousClass": currentClass,
        "classShiftedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;
      updated++;
      await commitIfNeeded();
    }

    await commitIfNeeded(force: true);
    return updated;
  }

  String? _nextClass(String className) {
    final index = AcademicCatalog.classValues.indexOf(className);
    if (index < 0 || index >= AcademicCatalog.classValues.length - 1) {
      return null;
    }
    return AcademicCatalog.classValues[index + 1];
  }

  Future<bool> _confirmTypedAction({
    required String title,
    required String message,
    required String expectedText,
    required String actionLabel,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 14),
              Text("Type $expectedText to continue."),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                controller.text.trim() == expectedText,
              ),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final userType = ref.watch(userTypeProvider);
    if (userType != "admin") {
      return Scaffold(
        appBar: AppBar(title: const Text("Settings")),
        body: const Center(child: Text("Only admins can open settings.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: const Color(0xFFF5F7FB),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SettingsSection(
                icon: Icons.dashboard_customize_outlined,
                title: "Dashboard Customization",
                subtitle: "Choose what appears on the Admin Dashboard.",
                child: const _DashboardPreferenceSettings(),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                icon: Icons.cleaning_services_outlined,
                title: "Session End",
                subtitle: "Clear academic records before a fresh session.",
                child: FilledButton.icon(
                  onPressed: _busy ? null : _resetAcademicSession,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text("Reset Academic Session"),
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                icon: Icons.trending_up_outlined,
                title: "Class Promotion",
                subtitle:
                    "Move active students and pending generated passwords smoothly.",
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _sourceClass,
                            decoration: const InputDecoration(
                              labelText: "From",
                              border: OutlineInputBorder(),
                            ),
                            items: AcademicCatalog.classValues
                                .where((value) => value != "12")
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      AcademicCatalog.classLabel(value),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _sourceClass = value;
                                      _targetClass =
                                          _nextClass(value) ?? _targetClass;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _targetClass,
                            decoration: const InputDecoration(
                              labelText: "To",
                              border: OutlineInputBorder(),
                            ),
                            items: AcademicCatalog.classValues
                                .where((value) => value != _sourceClass)
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      AcademicCatalog.classLabel(value),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _targetClass = value);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _shiftStudents(
                                promoteAll: false,
                                sourceClass: _sourceClass,
                                targetClass: _targetClass,
                              ),
                        icon: const Icon(Icons.compare_arrows_outlined),
                        label: const Text("Shift Selected Class"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _shiftStudents(promoteAll: true),
                        icon: const Icon(Icons.upgrade_outlined),
                        label: const Text("Promote All To Next Class"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: Center(
                  child: Container(
                    width: 260,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text(
                          _busyMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
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

class _DashboardPreferenceSettings extends StatelessWidget {
  const _DashboardPreferenceSettings();

  @override
  Widget build(BuildContext context) {
    final branding = WhiteLabelConfig.current;
    return StreamBuilder<AdminDashboardPreferences>(
      stream: AdminDashboardPreferences.stream(),
      initialData: AdminDashboardPreferences.defaults,
      builder: (context, snapshot) {
        final preferences = snapshot.data ?? AdminDashboardPreferences.defaults;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreferenceGroupLabel("OVERVIEW", color: branding.primaryColor),
            _DashboardPreferenceSwitch(
              title: "Students",
              subtitle: "Show total and active student metrics",
              value: preferences.showStudentOverview,
              onChanged: (value) =>
                  preferences.copyWith(showStudentOverview: value).save(),
            ),
            _DashboardPreferenceSwitch(
              title: "Attendance",
              subtitle: "Show today's marked attendance summary",
              value: preferences.showAttendanceOverview,
              onChanged: (value) =>
                  preferences.copyWith(showAttendanceOverview: value).save(),
            ),
            _DashboardPreferenceSwitch(
              title: "Teachers",
              subtitle: "Show active teacher count and pending signups",
              value: preferences.showTeacherOverview,
              onChanged: (value) =>
                  preferences.copyWith(showTeacherOverview: value).save(),
            ),
            const SizedBox(height: 12),
            _PreferenceGroupLabel("ALERTS", color: branding.primaryColor),
            _DashboardPreferenceSwitch(
              title: "3-Day Absence",
              subtitle:
                  "Show students absent for 3 consecutive attendance days",
              value: preferences.showConsecutiveAbsenceAlert,
              onChanged: (value) => preferences
                  .copyWith(showConsecutiveAbsenceAlert: value)
                  .save(),
            ),
            _DashboardPreferenceSwitch(
              title: "Pending Fees",
              subtitle: "Show outstanding fee metric and alert",
              value: preferences.showPendingFees,
              onChanged: (value) =>
                  preferences.copyWith(showPendingFees: value).save(),
            ),
            const SizedBox(height: 12),
            _PreferenceGroupLabel("CONTENT", color: branding.primaryColor),
            _DashboardPreferenceSwitch(
              title: "QR & App Link",
              subtitle: "Show public app sharing controls on dashboard",
              value: preferences.showQrAndAppLink,
              onChanged: (value) =>
                  preferences.copyWith(showQrAndAppLink: value).save(),
            ),
            _DashboardPreferenceSwitch(
              title: "Quick Actions",
              subtitle: "Show compact admin shortcuts",
              value: preferences.showQuickActions,
              onChanged: (value) =>
                  preferences.copyWith(showQuickActions: value).save(),
            ),
            _DashboardPreferenceSwitch(
              title: "Updates",
              subtitle: "Show the updates management section",
              value: preferences.showUpdates,
              onChanged: (value) =>
                  preferences.copyWith(showUpdates: value).save(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: AdminDashboardPreferences.reset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text("Reset Dashboard to Default"),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PreferenceGroupLabel extends StatelessWidget {
  const _PreferenceGroupLabel(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DashboardPreferenceSwitch extends StatelessWidget {
  const _DashboardPreferenceSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 42,
                width: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
