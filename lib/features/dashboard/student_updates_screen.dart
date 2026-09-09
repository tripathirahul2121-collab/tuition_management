import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';

class StudentUpdatesScreen extends StatelessWidget {
  const StudentUpdatesScreen({super.key});

  Stream<QuerySnapshot> _updatesStream(String className) {
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

  @override
  Widget build(BuildContext context) {
    final userData =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final className = userData?["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData?["batch"]?.toString(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text("Announcements"), centerTitle: true),

      body: StreamBuilder<QuerySnapshot>(
        stream: _updatesStream(className),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final target =
                data["target"]?.toString() ?? AcademicCatalog.allClassesTarget;
            final classMatches =
                target == AcademicCatalog.allClassesTarget ||
                target == className;
            return classMatches &&
                AcademicCatalog.updateBatchMatches(data, batchName);
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text("No announcements yet"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              final title = data["title"] ?? "";
              final message = data["message"] ?? "";
              final scheduledAt = (data["scheduledAt"] as Timestamp).toDate();
              final target =
                  data["target"]?.toString() ??
                  AcademicCatalog.allClassesTarget;

              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(16),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(message, style: const TextStyle(fontSize: 14)),

                      const SizedBox(height: 10),

                      Text(
                        DateFormat('dd MMM yyyy • hh:mm a').format(scheduledAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Chip(
                        avatar: const Icon(Icons.groups, size: 18),
                        label: Text(AcademicCatalog.classLabel(target)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
