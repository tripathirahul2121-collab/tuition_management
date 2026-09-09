import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';

class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({super.key});

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  DateTime selectedMonth = DateTime.now();
  static const double _absenceDateTileExtent = 70;

  final List<String> templates = [
    "Fever",
    "Stomach Pain",
    "Headache",
    "Stayback in School",
    "Doing School Homework",
    "Exam Preparation",
    "Overslept",
    "Other",
  ];

  ////////////////////////////////////////////////////////////
  /// MONTH NAVIGATION
  ////////////////////////////////////////////////////////////

  void nextMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1);
    });
  }

  void previousMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _monthlyAttendanceStream(
    String attendanceDocId,
  ) {
    final firstDay = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final lastDay = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final startKey = DateFormat("yyyy-MM-dd").format(firstDay);
    final endKey = DateFormat("yyyy-MM-dd").format(lastDay);

    return FirebaseFirestore.instance
        .collection("attendance")
        .doc(attendanceDocId)
        .collection("records")
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: startKey,
          isLessThanOrEqualTo: endKey,
        )
        .snapshots();
  }

  ////////////////////////////////////////////////////////////
  /// ABSENCE PANEL
  ////////////////////////////////////////////////////////////

  void _scrollAbsenceDateIntoView({
    required ScrollController controller,
    required List<DateTime> days,
    required DateTime selectedDate,
    bool animated = false,
  }) {
    if (!controller.hasClients) return;

    final index = days.indexWhere(
      (day) => DateUtils.isSameDay(day, selectedDate),
    );
    if (index < 0) return;

    final viewportWidth = controller.position.viewportDimension;
    final targetOffset =
        (index * _absenceDateTileExtent) -
        ((viewportWidth - _absenceDateTileExtent) / 2);
    final offset = targetOffset.clamp(0.0, controller.position.maxScrollExtent);

    if (animated) {
      controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(offset);
    }
  }

  void openAbsencePanel() {
    final userData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final studentMobile = userData["mobile"]?.toString() ?? "";
    final studentClass = userData["class"]?.toString() ?? "6";
    final studentBatch = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final attendanceDocId = AcademicCatalog.batchDocId(
      studentClass,
      studentBatch,
    );

    DateTime selectedDate = DateTime.now();
    String selectedReason = templates.first;
    final otherController = TextEditingController();
    final dateScrollController = ScrollController();
    final days = List.generate(
      15,
      (i) => DateTime.now()
          .subtract(const Duration(days: 7))
          .add(Duration(days: i)),
    );
    var didScrollToToday = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),

      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!didScrollToToday) {
              didScrollToToday = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollAbsenceDateIntoView(
                  controller: dateScrollController,
                  days: days,
                  selectedDate: selectedDate,
                );
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),

              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: maxHeight.clamp(0.0, constraints.maxHeight),
                      ),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            const Center(
                              child: Text(
                                "Report Absence",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            ////////////////////////////////////////////////////
                            /// DATE SELECTOR
                            ////////////////////////////////////////////////////
                            const Text(
                              "Select Date",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),

                            const SizedBox(height: 10),

                            SizedBox(
                              height: 70,

                              child: ListView.builder(
                                controller: dateScrollController,
                                scrollDirection: Axis.horizontal,
                                itemCount: days.length,

                                itemBuilder: (_, index) {
                                  final day = days[index];
                                  final isSelected = DateUtils.isSameDay(
                                    day,
                                    selectedDate,
                                  );

                                  return GestureDetector(
                                    onTap: () {
                                      setState(() => selectedDate = day);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            _scrollAbsenceDateIntoView(
                                              controller: dateScrollController,
                                              days: days,
                                              selectedDate: day,
                                              animated: true,
                                            );
                                          });
                                    },

                                    child: Container(
                                      width: 60,
                                      margin: const EdgeInsets.only(right: 10),

                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.grey.shade200,

                                        borderRadius: BorderRadius.circular(12),
                                      ),

                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            DateFormat("EEE").format(day),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),

                                          const SizedBox(height: 4),

                                          Text(
                                            day.day.toString(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 20),

                            ////////////////////////////////////////////////////
                            /// REASON CHIPS
                            ////////////////////////////////////////////////////
                            const Text(
                              "Reason",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),

                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: templates.map((r) {
                                final selected = selectedReason == r;

                                return ChoiceChip(
                                  label: Text(r),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() => selectedReason = r);
                                  },
                                );
                              }).toList(),
                            ),

                            if (selectedReason == "Other")
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TextField(
                                  controller: otherController,
                                  decoration: const InputDecoration(
                                    labelText: "Enter reason",
                                  ),
                                  minLines: 1,
                                  maxLines: 3,
                                  textInputAction: TextInputAction.done,
                                ),
                              ),

                            const SizedBox(height: 20),

                            ////////////////////////////////////////////////////
                            /// SUBMIT
                            ////////////////////////////////////////////////////
                            SizedBox(
                              width: double.infinity,

                              child: ElevatedButton(
                                onPressed: () async {
                                  final reason = selectedReason == "Other"
                                      ? otherController.text.trim()
                                      : selectedReason;

                                  if (reason.isEmpty) return;

                                  final dateKey = DateFormat(
                                    "yyyy-MM-dd",
                                  ).format(selectedDate);

                                  final doc = await FirebaseFirestore.instance
                                      .collection("attendance")
                                      .doc(attendanceDocId)
                                      .collection("records")
                                      .doc(dateKey)
                                      .get();

                                  if (doc.exists) {
                                    final data =
                                        doc.data() as Map<String, dynamic>;

                                    if (data["reason_$studentMobile"] != null) {
                                      if (!context.mounted) return;

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Reason already submitted",
                                          ),
                                        ),
                                      );

                                      return;
                                    }
                                  }

                                  await FirebaseFirestore.instance
                                      .collection("attendance")
                                      .doc(attendanceDocId)
                                      .collection("records")
                                      .doc(dateKey)
                                      .set({
                                        "reason_$studentMobile": reason,
                                      }, SetOptions(merge: true));

                                  if (!context.mounted) return;

                                  Navigator.pop(context);
                                },

                                child: const Text("Submit"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      dateScrollController.dispose();
      otherController.dispose();
    });
  }

  ////////////////////////////////////////////////////////////
  /// CALENDAR GRID
  ////////////////////////////////////////////////////////////

  Widget buildCalendar(Map<String, dynamic> records, String studentMobile) {
    final firstDay = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final lastDay = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);

    final totalDays = lastDay.day;
    final leadingBlankDays = firstDay.weekday % 7;
    final totalCalendarCells = leadingBlankDays + totalDays;
    const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

    return Column(
      children: [
        Row(
          children: weekdays.map((day) {
            final isSunday = day == "Sun";

            return Expanded(
              child: Center(
                child: Text(
                  day,
                  style: TextStyle(
                    color: isSunday
                        ? Colors.red.shade700
                        : Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCalendarCells,

          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            mainAxisExtent: 52,
          ),

          itemBuilder: (_, index) {
            if (index < leadingBlankDays) {
              return const SizedBox.shrink();
            }

            final day = index - leadingBlankDays + 1;
            final date = DateTime(selectedMonth.year, selectedMonth.month, day);
            final key = DateFormat("yyyy-MM-dd").format(date);
            final data = records[key] as Map<String, dynamic>?;
            final reason =
                data?["reason_$studentMobile"]?.toString().trim() ?? "";
            final attendance = data?[studentMobile];
            final isPresent = attendance == true;
            final isAbsent = attendance == false;
            final hasReason = reason.isNotEmpty;
            final isToday = DateUtils.isSameDay(date, DateTime.now());

            Color color = Colors.grey.shade200;
            Color textColor = Colors.black87;
            Color borderColor = Colors.transparent;
            IconData? statusIcon;

            if (isPresent) {
              color = Colors.green.shade700;
              textColor = Colors.white;
              statusIcon = Icons.check_circle;
            } else if (isAbsent) {
              color = Colors.red.shade700;
              textColor = Colors.white;
              statusIcon = Icons.cancel;
            } else if (hasReason) {
              color = Colors.orange.shade700;
              textColor = Colors.white;
              statusIcon = Icons.info;
            }

            if (isToday && !isPresent && !isAbsent && !hasReason) {
              borderColor = Theme.of(context).colorScheme.primary;
            }

            return GestureDetector(
              onTap: () {
                final formattedDate = DateFormat(
                  "EEE, dd MMM yyyy",
                ).format(date);
                final status = isPresent
                    ? "Present"
                    : isAbsent
                    ? "Absent"
                    : hasReason
                    ? "Absence reported"
                    : "No attendance record";

                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(formattedDate),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: TextStyle(
                            color: isPresent
                                ? Colors.green.shade700
                                : (isAbsent || hasReason)
                                ? Colors.red.shade700
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (hasReason) ...[
                          const SizedBox(height: 12),
                          const Text(
                            "Reason",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(reason),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
              },

              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 1.4),
                ),

                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat("EEE").format(date),
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.82),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "$day",
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (statusIcon != null)
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Icon(statusIcon, color: textColor, size: 10),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final userData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final studentMobile = userData["mobile"]?.toString() ?? "";
    final studentClass = userData["class"]?.toString() ?? "6";
    final studentBatch = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final attendanceDocId = AcademicCatalog.batchDocId(
      studentClass,
      studentBatch,
    );

    return Scaffold(
      appBar: AppBar(title: const Text("My Attendance")),

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _monthlyAttendanceStream(attendanceDocId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          Map<String, dynamic> records = {};

          int total = 0;
          int present = 0;
          int absent = 0;

          for (var doc in snapshot.data!.docs) {
            final data = doc.data();

            records[doc.id] = data;

            if (data.containsKey(studentMobile)) {
              total++;

              if (data[studentMobile] == true) {
                present++;
              } else {
                absent++;
              }
            }
          }

          double percent = total == 0 ? 0 : (present / total) * 100;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),

            child: Column(
              children: [
                ////////////////////////////////////////////////////
                /// MONTH HEADER
                ////////////////////////////////////////////////////
                Row(
                  children: [
                    IconButton(
                      onPressed: previousMonth,
                      icon: const Icon(Icons.arrow_back_ios),
                    ),

                    Expanded(
                      child: Center(
                        child: Text(
                          DateFormat("MMMM yyyy").format(selectedMonth),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    IconButton(
                      onPressed: nextMonth,
                      icon: const Icon(Icons.arrow_forward_ios),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                ////////////////////////////////////////////////////
                /// STATS CARD
                ////////////////////////////////////////////////////
                Container(
                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xff6A5ACD), Color(0xff7F7FD5)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),

                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,

                    children: [
                      stat("Total", total),
                      stat("Present", present),
                      stat("Absent", absent),
                      stat("Attendance", "${percent.toStringAsFixed(0)}%"),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                ////////////////////////////////////////////////////
                /// CALENDAR GRID
                ////////////////////////////////////////////////////
                buildCalendar(records, studentMobile),
              ],
            ),
          );
        },
      ),

      ////////////////////////////////////////////////////////////
      /// REPORT ABSENCE
      ////////////////////////////////////////////////////////////
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.report),
        label: const Text("Report Absence"),
        onPressed: openAbsencePanel,
      ),
    );
  }

  Widget stat(String title, dynamic value) {
    return Column(
      children: [
        Text(
          "$value",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),

        Text(title, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
