import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String selectedClass = "6";
  String selectedBatch = AcademicCatalog.regularBatch;
  DateTime selectedDate = DateTime.now();
  DateTime currentMonth = DateTime.now();
  final ScrollController _dateScrollController = ScrollController();

  final Map<String, bool> attendanceMap = {};
  List<_AttendanceStudent> _currentStudents = const [];
  String? _studentsStreamClass;
  String? _studentsStreamBatch;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _cachedStudentsStream;
  String? _attendanceStreamKey;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _cachedAttendanceStream;
  bool isViewMode = false;
  bool _isSavingAttendance = false;

  String get dateKey => DateFormat('yyyy-MM-dd').format(selectedDate);
  String get _attendanceDocId =>
      AcademicCatalog.batchDocId(selectedClass, selectedBatch);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedDate();
    });
  }

  @override
  void dispose() {
    _dateScrollController.dispose();
    super.dispose();
  }

  void _scrollToSelectedDate() {
    if (!_dateScrollController.hasClients) return;

    final selectedMonth = DateTime(selectedDate.year, selectedDate.month);
    final visibleMonth = DateTime(currentMonth.year, currentMonth.month);

    if (selectedMonth != visibleMonth) return;

    const itemExtent = 82.0; // card width + horizontal margin
    final viewportWidth = _dateScrollController.position.viewportDimension;
    final targetOffset =
        ((selectedDate.day - 1) * itemExtent) -
        ((viewportWidth - itemExtent) / 2);
    final maxOffset = _dateScrollController.position.maxScrollExtent;

    _dateScrollController.jumpTo(targetOffset.clamp(0.0, maxOffset));
  }

  DateTime _defaultDateForMonth(DateTime month) {
    final today = DateTime.now();
    final isCurrentMonth =
        today.year == month.year && today.month == month.month;

    return isCurrentMonth ? today : DateTime(month.year, month.month, 1);
  }

  ////////////////////////////////////////////////////////////
  /// STREAMS
  ////////////////////////////////////////////////////////////

  Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream() {
    if (_studentsStreamClass == selectedClass &&
        _studentsStreamBatch == selectedBatch &&
        _cachedStudentsStream != null) {
      return _cachedStudentsStream!;
    }

    _studentsStreamClass = selectedClass;
    _studentsStreamBatch = selectedBatch;
    _cachedStudentsStream = FirebaseFirestore.instance
        .collection("users")
        .where("role", isEqualTo: "student")
        .where("class", isEqualTo: selectedClass)
        .orderBy("name")
        .snapshots();

    return _cachedStudentsStream!;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _attendanceStream() {
    final key = "$selectedClass|$selectedBatch|$dateKey";
    if (_attendanceStreamKey == key && _cachedAttendanceStream != null) {
      return _cachedAttendanceStream!;
    }

    _attendanceStreamKey = key;
    _cachedAttendanceStream = FirebaseFirestore.instance
        .collection("attendance")
        .doc(_attendanceDocId)
        .collection("records")
        .doc(dateKey)
        .snapshots();

    return _cachedAttendanceStream!;
  }

  Query<Map<String, dynamic>> _monthlyAttendanceQuery() {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    final startKey = DateFormat("yyyy-MM-dd").format(firstDay);
    final endKey = DateFormat("yyyy-MM-dd").format(lastDay);

    return FirebaseFirestore.instance
        .collection("attendance")
        .doc(_attendanceDocId)
        .collection("records")
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: startKey,
          isLessThanOrEqualTo: endKey,
        );
  }

  ////////////////////////////////////////////////////////////
  /// DAYS OF MONTH
  ////////////////////////////////////////////////////////////

  List<DateTime> getDaysOfMonth() {
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);

    return List.generate(
      lastDay.day,
      (index) => DateTime(currentMonth.year, currentMonth.month, index + 1),
    );
  }

  Future<Map<int, _MonthlyAttendanceDay>> _loadStudentMonthlyAttendance(
    String mobile,
  ) async {
    final snap = await _monthlyAttendanceQuery().get();

    final monthData = <int, _MonthlyAttendanceDay>{};

    for (final doc in snap.docs) {
      final date = DateTime.tryParse(doc.id);
      if (date == null) continue;

      final data = doc.data();
      final value = data[mobile];
      if (value is bool) {
        monthData[date.day] = _MonthlyAttendanceDay(
          present: value,
          reason: data["reason_$mobile"]?.toString().trim() ?? "",
        );
      }
    }

    return monthData;
  }

  Future<void> _showStudentMonthlyCalendar({
    required String mobile,
    required String name,
  }) async {
    final month = DateTime(currentMonth.year, currentMonth.month);
    final days = getDaysOfMonth();
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: FutureBuilder<Map<int, _MonthlyAttendanceDay>>(
              future: _loadStudentMonthlyAttendance(mobile),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final attendance = snapshot.data!;
                final present = attendance.values
                    .where((v) => v.present)
                    .length;
                final absent = attendance.values
                    .where((v) => !v.present)
                    .length;
                final totalMarked = present + absent;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                DateFormat('MMMM yyyy').format(month),
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _calendarLegend("Present", Colors.green),
                        _calendarLegend("Absent", Colors.red),
                        _calendarLegend("No record", Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: const [
                        _WeekdayLabel("Mon"),
                        _WeekdayLabel("Tue"),
                        _WeekdayLabel("Wed"),
                        _WeekdayLabel("Thu"),
                        _WeekdayLabel("Fri"),
                        _WeekdayLabel("Sat"),
                        _WeekdayLabel("Sun"),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: days.length + firstWeekday - 1,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemBuilder: (context, index) {
                        if (index < firstWeekday - 1) {
                          return const SizedBox.shrink();
                        }

                        final day = index - firstWeekday + 2;
                        final record = attendance[day];
                        final color = record?.present == true
                            ? Colors.green
                            : record?.present == false
                            ? Colors.red
                            : Colors.grey;

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: record?.present == false
                              ? () => _showAbsenceReasonDialog(
                                  day: day,
                                  name: name,
                                  reason: record?.reason ?? "",
                                )
                              : null,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: color.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  "$day",
                                  style: TextStyle(
                                    color: color.shade700,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (record?.present == false)
                                  Positioned(
                                    right: 5,
                                    top: 5,
                                    child: Icon(
                                      record!.reason.isEmpty
                                          ? Icons.info_outline
                                          : Icons.notes,
                                      size: 12,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildStatsBar(totalMarked, present, absent),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showAbsenceReasonDialog({
    required int day,
    required String name,
    required String reason,
  }) {
    final date = DateTime(currentMonth.year, currentMonth.month, day);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(DateFormat("dd MMM yyyy").format(date)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$name was absent",
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Reason",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(reason.isEmpty ? "Reason not mentioned yet" : reason),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  ////////////////////////////////////////////////////////////
  /// SAVE
  ////////////////////////////////////////////////////////////

  Future<void> _saveAttendance() async {
    if (_isSavingAttendance) return;

    final validMobiles = _currentStudents
        .map((student) => student.mobile)
        .toSet();
    if (validMobiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No active students found")));
      return;
    }

    attendanceMap.removeWhere((mobile, _) => !validMobiles.contains(mobile));

    setState(() => _isSavingAttendance = true);

    try {
      final recordRef = FirebaseFirestore.instance
          .collection("attendance")
          .doc(_attendanceDocId)
          .collection("records")
          .doc(dateKey);
      final existing = await recordRef.get();
      final sanitizedData = <String, dynamic>{};

      if (existing.exists) {
        final existingData = existing.data() ?? {};
        for (final entry in existingData.entries) {
          if (entry.key.startsWith("reason_")) {
            final mobile = entry.key.substring("reason_".length);
            if (validMobiles.contains(mobile)) {
              sanitizedData[entry.key] = entry.value;
            }
          }
        }
      }

      for (final student in _currentStudents) {
        sanitizedData[student.mobile] = attendanceMap[student.mobile] ?? true;
      }

      await recordRef.set(sanitizedData);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Attendance Saved")));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to save attendance")),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingAttendance = false);
      }
    }
  }

  ////////////////////////////////////////////////////////////
  /// UI
  ////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final daysOfMonth = getDaysOfMonth();

    return Scaffold(
      backgroundColor: const Color(0xffF7F4FB),
      appBar: AppBar(title: const Text("Attendance")),
      bottomNavigationBar: isViewMode ? null : _buildFooter(),

      body: Column(
        children: [
          //////////////////////////////////////////////////////
          /// TOGGLE
          //////////////////////////////////////////////////////
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text("Take")),
                ButtonSegment(value: true, label: Text("View")),
              ],
              selected: {isViewMode},
              onSelectionChanged: (val) {
                setState(() {
                  isViewMode = val.first;
                  attendanceMap.clear();
                  _currentStudents = const [];
                });
              },
            ),
          ),

          //////////////////////////////////////////////////////
          /// CLASS
          //////////////////////////////////////////////////////
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: selectedClass,
              decoration: const InputDecoration(labelText: "Class"),
              items: AcademicCatalog.classValues.map((value) {
                return DropdownMenuItem(
                  value: value,
                  child: Text(AcademicCatalog.classLabel(value)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    selectedClass = val;
                    attendanceMap.clear();
                    _currentStudents = const [];
                  });
                }
              },
            ),
          ),

          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: selectedBatch,
              decoration: const InputDecoration(labelText: "Batch"),
              items: AcademicCatalog.batchValues.map((value) {
                return DropdownMenuItem(
                  value: value,
                  child: Text(AcademicCatalog.batchLabel(value)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    selectedBatch = AcademicCatalog.normalizeBatch(val);
                    attendanceMap.clear();
                    _currentStudents = const [];
                  });
                }
              },
            ),
          ),

          const SizedBox(height: 10),

          //////////////////////////////////////////////////////
          /// MONTH SWITCHER (NOW IN BOTH MODES)
          //////////////////////////////////////////////////////
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () {
                  setState(() {
                    currentMonth = DateTime(
                      currentMonth.year,
                      currentMonth.month - 1,
                    );
                    selectedDate = _defaultDateForMonth(currentMonth);
                    attendanceMap.clear();
                    _currentStudents = const [];
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToSelectedDate();
                  });
                },
              ),

              Text(
                DateFormat('MMMM yyyy').format(currentMonth),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: () {
                  setState(() {
                    currentMonth = DateTime(
                      currentMonth.year,
                      currentMonth.month + 1,
                    );
                    selectedDate = _defaultDateForMonth(currentMonth);
                    attendanceMap.clear();
                    _currentStudents = const [];
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToSelectedDate();
                  });
                },
              ),
            ],
          ),

          //////////////////////////////////////////////////////
          /// CALENDAR (NOW IN BOTH MODES)
          //////////////////////////////////////////////////////
          SizedBox(
            height: 80,
            child: ListView.builder(
              controller: _dateScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: daysOfMonth.length,
              itemBuilder: (context, index) {
                final date = daysOfMonth[index];
                final isSelected =
                    DateFormat('yyyy-MM-dd').format(date) == dateKey;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedDate = date;
                      attendanceMap.clear();
                      _currentStudents = const [];
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToSelectedDate();
                    });
                  },
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('dd').format(date)),
                        Text(DateFormat('EEE').format(date)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          //////////////////////////////////////////////////////
          /// BODY
          //////////////////////////////////////////////////////
          Expanded(child: isViewMode ? _buildViewMode() : _buildTakeMode()),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// TAKE MODE
  ////////////////////////////////////////////////////////////

  Widget _buildTakeMode() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _studentsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final students = _activeStudentsFrom(snapshot.data!.docs);
        _syncCurrentStudents(students);

        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: students.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final student = students[index];
                  final name = student.name;
                  final mobile = student.mobile;

                  attendanceMap.putIfAbsent(mobile, () => true);

                  final present = attendanceMap[mobile]!;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _numberBadge(index + 1),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                present ? "Present" : "Absent",
                                style: TextStyle(
                                  color: present
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: present,
                          activeThumbColor: Colors.green,
                          inactiveThumbColor: Colors.red,
                          onChanged: (val) {
                            attendanceMap[mobile] = val;
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _buildTakeStats(students),
          ],
        );
      },
    );
  }

  ////////////////////////////////////////////////////////////
  /// VIEW MODE
  ////////////////////////////////////////////////////////////

  Widget _buildViewMode() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _studentsStream(),
      builder: (context, studentsSnapshot) {
        if (!studentsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final studentDirectory = <String, Map<String, dynamic>>{};
        for (final student in _activeStudentsFrom(
          studentsSnapshot.data!.docs,
        )) {
          studentDirectory[student.mobile] = {
            "name": student.name,
            "mobile": student.mobile,
          };
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _attendanceStream(),
          builder: (context, attendanceSnapshot) {
            if (!attendanceSnapshot.hasData ||
                !attendanceSnapshot.data!.exists) {
              return Column(
                children: [
                  const Expanded(child: Center(child: Text("No Record Found"))),
                  _buildStatsBar(0, 0, 0),
                ],
              );
            }

            final data = attendanceSnapshot.data!.data() ?? {};
            final list = _viewRowsFrom(data, studentDirectory);
            final total = list.length;
            final present = list.where((item) => item.present).length;
            final absent = total - present;

            if (list.isEmpty) {
              return Column(
                children: [
                  const Expanded(child: Center(child: Text("No Record Found"))),
                  _buildStatsBar(0, 0, 0),
                ],
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = list[index];
                      final isPresent = item.present;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: (isPresent ? Colors.green : Colors.red)
                                .withValues(alpha: 0.18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),

                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _numberBadge(index + 1),
                            const SizedBox(width: 12),
                            Icon(
                              isPresent ? Icons.check_circle : Icons.cancel,
                              color: isPresent ? Colors.green : Colors.red,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isPresent ? "Present" : "Absent",
                                    style: TextStyle(
                                      color: isPresent
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (!isPresent) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.reason.isEmpty
                                            ? Colors.red.shade50
                                            : Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        item.reason.isEmpty
                                            ? "Reason not mentioned yet"
                                            : "Reason: ${item.reason}",
                                        style: TextStyle(
                                          color: item.reason.isEmpty
                                              ? Colors.red.shade700
                                              : Colors.orange.shade900,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: "Monthly calendar",
                              onPressed: () => _showStudentMonthlyCalendar(
                                mobile: item.mobile,
                                name: item.name,
                              ),
                              icon: const Icon(Icons.calendar_month),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _buildStatsBar(total, present, absent),
              ],
            );
          },
        );
      },
    );
  }

  List<_AttendanceStudentRow> _viewRowsFrom(
    Map<String, dynamic> attendanceData,
    Map<String, Map<String, dynamic>> studentDirectory,
  ) {
    final rows = <_AttendanceStudentRow>[];

    for (final entry in attendanceData.entries) {
      if (entry.value is! bool) continue;
      final student = studentDirectory[entry.key];
      if (student == null) continue;

      rows.add(
        _AttendanceStudentRow(
          mobile: entry.key,
          name: student["name"]?.toString() ?? entry.key,
          present: entry.value == true,
          reason:
              attendanceData["reason_${entry.key}"]?.toString().trim() ?? "",
        ),
      );
    }

    rows.sort((a, b) {
      if (a.present != b.present) return a.present ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return rows;
  }

  ////////////////////////////////////////////////////////////
  /// STATS
  ////////////////////////////////////////////////////////////

  Widget _buildTakeStats(List<_AttendanceStudent> students) {
    final validMobiles = students.map((student) => student.mobile).toSet();
    final total = validMobiles.length;
    final present = validMobiles
        .where((mobile) => attendanceMap[mobile] ?? true)
        .length;
    final absent = total - present;

    return _buildStatsBar(total, present, absent);
  }

  List<_AttendanceStudent> _activeStudentsFrom(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final byMobile = <String, _AttendanceStudent>{};

    for (final doc in docs) {
      final data = doc.data();
      if (data["active"] == false) continue;
      if (!AcademicCatalog.batchMatches(data, selectedBatch)) continue;

      final name = data["name"]?.toString().trim();
      byMobile[doc.id] = _AttendanceStudent(
        mobile: doc.id,
        name: name == null || name.isEmpty ? "Unnamed" : name,
      );
    }

    final students = byMobile.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return students;
  }

  void _syncCurrentStudents(List<_AttendanceStudent> students) {
    _currentStudents = students;

    final validMobiles = students.map((student) => student.mobile).toSet();
    attendanceMap.removeWhere((mobile, _) => !validMobiles.contains(mobile));
    for (final student in students) {
      attendanceMap.putIfAbsent(student.mobile, () => true);
    }
  }

  Widget _buildStatsBar(int total, int present, int absent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Total: $total"),
          Text(
            "Present: $present",
            style: const TextStyle(color: Colors.green),
          ),
          Text("Absent: $absent", style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////
  /// FOOTER
  ////////////////////////////////////////////////////////////

  Widget _buildFooter() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSavingAttendance ? null : _saveAttendance,
            icon: _isSavingAttendance
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(
              _isSavingAttendance ? "Saving Attendance..." : "Save Attendance",
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberBadge(int number) {
    return Container(
      height: 30,
      width: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        "$number",
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _calendarLegend(String label, MaterialColor color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MonthlyAttendanceDay {
  const _MonthlyAttendanceDay({required this.present, required this.reason});

  final bool present;
  final String reason;
}

class _AttendanceStudent {
  const _AttendanceStudent({required this.mobile, required this.name});

  final String mobile;
  final String name;
}

class _AttendanceStudentRow {
  const _AttendanceStudentRow({
    required this.mobile,
    required this.name,
    required this.present,
    required this.reason,
  });

  final String mobile;
  final String name;
  final bool present;
  final String reason;
}
