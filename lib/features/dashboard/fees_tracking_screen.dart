import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FeesTrackingScreen extends StatefulWidget {
  const FeesTrackingScreen({super.key});

  @override
  State<FeesTrackingScreen> createState() => _FeesTrackingScreenState();
}

class _FeesTrackingScreenState extends State<FeesTrackingScreen> {
  String selectedClass = "6";
  String mode = "monthly";
  String sortFilter = "latest";

  final monthlyController = TextEditingController();
  final annualController = TextEditingController();
  final installmentController = TextEditingController();

  bool _controllersSynced = false;

  final List<Map<String, String>> classes = const [
    {"value": "5", "label": "Class 5"},
    {"value": "6", "label": "Class 6"},
    {"value": "7", "label": "Class 7"},
    {"value": "8", "label": "Class 8"},
    {"value": "9", "label": "Class 9"},
    {"value": "10", "label": "Class 10"},
    {"value": "11", "label": "Class 11"},
    {"value": "12", "label": "Class 12"},
  ];

  DocumentReference<Map<String, dynamic>> get _feesDoc =>
      FirebaseFirestore.instance.collection("fees").doc("Class-$selectedClass");

  @override
  void dispose() {
    monthlyController.dispose();
    annualController.dispose();
    installmentController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _money(num value) {
    final amount = value.toDouble();
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount.toStringAsFixed(2);
  }

  void _syncControllers(Map<String, dynamic> feeData) {
    if (_controllersSynced) return;

    final savedMode = feeData["mode"]?.toString();
    if (savedMode == "monthly" || savedMode == "annual") {
      mode = savedMode!;
    }

    monthlyController.text = _money(_numValue(feeData["monthlyFee"]));
    annualController.text = _money(_numValue(feeData["totalAnnualFee"]));
    installmentController.text = _money(_numValue(feeData["installment"]));
    _controllersSynced = true;
  }

  num _numValue(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? "") ?? 0;
  }

  Future<void> _saveFees() async {
    final monthlyFee = double.tryParse(monthlyController.text.trim()) ?? 0;
    final annualFee = double.tryParse(annualController.text.trim()) ?? 0;
    final installment = double.tryParse(installmentController.text.trim()) ?? 0;

    if (mode == "monthly" && monthlyFee <= 0) {
      _showSnack("Enter monthly fee");
      return;
    }

    if (mode == "annual" && (annualFee <= 0 || installment <= 0)) {
      _showSnack("Enter annual fee and monthly installment");
      return;
    }

    await _feesDoc.set({
      "class": selectedClass,
      "mode": mode,
      "monthlyFee": monthlyFee,
      "totalAnnualFee": annualFee,
      "installment": installment,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _showSnack("Fees saved");
  }

  Future<void> _addPayment({
    required String mobile,
    required double amount,
    required DateTime paidOn,
  }) async {
    final doc = await _feesDoc.get();
    final raw = doc.data() ?? {};
    final studentsRaw = raw["students"];
    final students = studentsRaw is Map<String, dynamic>
        ? studentsRaw
        : <String, dynamic>{};

    final existingStudent = students[mobile];
    final studentData = existingStudent is Map<String, dynamic>
        ? Map<String, dynamic>.from(existingStudent)
        : <String, dynamic>{};

    final payments = List<dynamic>.from(studentData["payments"] ?? []);
    payments.add({
      "amount": amount,
      "date": Timestamp.fromDate(paidOn),
      "recordedAt": Timestamp.now(),
    });

    await _feesDoc.set({
      "students": {
        mobile: {"payments": payments},
      },
    }, SetOptions(merge: true));

    _showSnack("Payment saved");
  }

  Future<void> _showAddPaymentSheet({
    required String name,
    required String mobile,
    required double suggestedAmount,
  }) async {
    final controller = TextEditingController(
      text: suggestedAmount > 0 ? _money(suggestedAmount) : "",
    );
    DateTime selectedDate = DateTime.now();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Add Payment",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(name),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Amount Paid",
                      prefixText: "Rs ",
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Payment Date"),
                    subtitle: Text(
                      DateFormat("dd MMM yyyy").format(selectedDate),
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );

                      if (picked != null) {
                        setSheetState(() => selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount =
                            double.tryParse(controller.text.trim()) ?? 0;

                        if (amount <= 0) {
                          _showSnack("Enter amount");
                          return;
                        }

                        Navigator.pop(sheetContext);
                        await _addPayment(
                          mobile: mobile,
                          amount: amount,
                          paidOn: selectedDate,
                        );
                      },
                      child: const Text("Save Payment"),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  void _showHistory(String name, List<dynamic> payments) {
    final sorted = [...payments];
    sorted.sort((a, b) {
      final aDate = _paymentDate(a);
      final bDate = _paymentDate(b);
      return bDate.compareTo(aDate);
    });

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                "$name History",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: sorted.isEmpty
                    ? const Center(child: Text("No payments yet"))
                    : ListView.builder(
                        itemCount: sorted.length,
                        itemBuilder: (_, i) {
                          final payment = sorted[i] as Map<String, dynamic>;
                          final date = _paymentDate(payment);
                          final amount = (payment["amount"] ?? 0) as num;

                          return ListTile(
                            title: Text("Rs ${_money(amount)}"),
                            subtitle: Text(
                              DateFormat("dd MMM yyyy").format(date),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  DateTime _paymentDate(dynamic payment) {
    if (payment is! Map<String, dynamic>) return DateTime(2000);
    final date = payment["date"];
    if (date is Timestamp) return date.toDate();
    return DateTime(2000);
  }

  bool _isCurrentMonth(DateTime date) {
    final now = DateTime.now();
    return date.month == now.month && date.year == now.year;
  }

  double _paidInCurrentMonth(List<dynamic> payments) {
    return payments.fold<double>(0, (total, payment) {
      if (payment is! Map<String, dynamic>) return total;
      final date = _paymentDate(payment);
      if (!_isCurrentMonth(date)) return total;
      return total + ((payment["amount"] ?? 0) as num).toDouble();
    });
  }

  double _totalPaid(List<dynamic> payments) {
    return payments.fold<double>(0, (total, payment) {
      if (payment is! Map<String, dynamic>) return total;
      return total + ((payment["amount"] ?? 0) as num).toDouble();
    });
  }

  DateTime _latestPaymentDate(List<dynamic> payments) {
    if (payments.isEmpty) return DateTime(2000);

    return payments.map(_paymentDate).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  List<QueryDocumentSnapshot> _sortedStudents(
    List<QueryDocumentSnapshot> students,
    Map<String, dynamic> studentsData,
  ) {
    final list = [...students];

    List<dynamic> paymentsFor(String mobile) {
      final data = studentsData[mobile];
      if (data is Map<String, dynamic>) {
        return List<dynamic>.from(data["payments"] ?? []);
      }
      return [];
    }

    String nameOf(QueryDocumentSnapshot doc) =>
        (doc["name"] ?? "").toString().toLowerCase();

    if (sortFilter == "defaulters") {
      list.removeWhere((doc) => _paidInCurrentMonth(paymentsFor(doc.id)) > 0);
      list.sort((a, b) => nameOf(a).compareTo(nameOf(b)));
      return list;
    }

    if (sortFilter == "alphabetical") {
      list.sort((a, b) => nameOf(a).compareTo(nameOf(b)));
      return list;
    }

    if (sortFilter == "minimum") {
      list.sort((a, b) {
        final paidCompare = _totalPaid(
          paymentsFor(a.id),
        ).compareTo(_totalPaid(paymentsFor(b.id)));
        if (paidCompare != 0) return paidCompare;
        return nameOf(a).compareTo(nameOf(b));
      });
      return list;
    }

    list.sort((a, b) {
      final dateCompare = _latestPaymentDate(
        paymentsFor(b.id),
      ).compareTo(_latestPaymentDate(paymentsFor(a.id)));
      if (dateCompare != 0) return dateCompare;
      return nameOf(a).compareTo(nameOf(b));
    });

    return list;
  }

  double _suggestedAmount(Map<String, dynamic> feeData) {
    final currentMode = feeData["mode"]?.toString() ?? mode;
    if (currentMode == "annual") {
      return ((feeData["installment"] ?? 0) as num).toDouble();
    }

    return ((feeData["monthlyFee"] ?? 0) as num).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fees Management")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _feesDoc.snapshots(),
        builder: (context, feeSnap) {
          final feeData = feeSnap.data?.data() ?? {};
          _syncControllers(feeData);

          return Column(
            children: [
              _buildControlPanel(feeData),
              Expanded(child: _buildStudentsList(feeData)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlPanel(Map<String, dynamic> feeData) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey("class-$selectedClass"),
            initialValue: selectedClass,
            decoration: const InputDecoration(labelText: "Class"),
            items: classes.map((c) {
              return DropdownMenuItem(
                value: c["value"],
                child: Text(c["label"]!),
              );
            }).toList(),
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                selectedClass = val;
                _controllersSynced = false;
              });
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: ValueKey("mode-$mode"),
            segments: const [
              ButtonSegment(value: "monthly", label: Text("Monthly")),
              ButtonSegment(value: "annual", label: Text("Annual")),
            ],
            selected: {mode},
            onSelectionChanged: (val) {
              setState(() => mode = val.first);
            },
          ),
          const SizedBox(height: 12),
          if (mode == "monthly")
            TextField(
              controller: monthlyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Monthly Fee"),
            ),
          if (mode == "annual") ...[
            TextField(
              controller: annualController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Total Annual Fee"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: installmentController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Monthly Installment",
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveFees,
              icon: const Icon(Icons.save),
              label: const Text("Save Fees"),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: "latest", label: Text("Latest")),
                ButtonSegment(
                  value: "alphabetical",
                  label: Text("Alphabetical"),
                ),
                ButtonSegment(value: "minimum", label: Text("Minimum")),
                ButtonSegment(value: "defaulters", label: Text("Defaulters")),
              ],
              selected: {sortFilter},
              onSelectionChanged: (val) {
                setState(() => sortFilter = val.first);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsList(Map<String, dynamic> feeData) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .where("role", isEqualTo: "student")
          .where("class", isEqualTo: selectedClass)
          .orderBy("name")
          .snapshots(),
      builder: (context, studentSnap) {
        if (!studentSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawStudents = feeData["students"];
        final studentsData = rawStudents is Map<String, dynamic>
            ? rawStudents
            : <String, dynamic>{};
        final activeStudents = studentSnap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data["active"] != false;
        }).toList();
        final students = _sortedStudents(activeStudents, studentsData);

        if (students.isEmpty) {
          return Center(
            child: Text(
              sortFilter == "defaulters"
                  ? "No defaulters for this month"
                  : "No students found",
            ),
          );
        }

        return ListView.builder(
          itemCount: students.length,
          itemBuilder: (_, i) {
            final student = students[i];
            final data = student.data() as Map<String, dynamic>;
            final name = data["name"]?.toString() ?? "Student";
            final mobile = student.id;
            final studentFeeData = studentsData[mobile];
            final payments = studentFeeData is Map<String, dynamic>
                ? List<dynamic>.from(studentFeeData["payments"] ?? [])
                : <dynamic>[];
            final paidThisMonth = _paidInCurrentMonth(payments);
            final totalPaid = _totalPaid(payments);
            final latestDate = _latestPaymentDate(payments);
            final isPaid = paidThisMonth > 0;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(child: Text(name[0].toUpperCase())),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text("Total paid: Rs ${_money(totalPaid)}"),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            isPaid ? "Paid" : "Pending",
                            style: TextStyle(
                              color: isPaid
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showHistory(name, payments),
                          icon: const Icon(Icons.history),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("Paid this month: Rs ${_money(paidThisMonth)}"),
                    Text(
                      payments.isEmpty
                          ? "Latest: No payment yet"
                          : "Latest: ${DateFormat("dd MMM yyyy").format(latestDate)}",
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showAddPaymentSheet(
                          name: name,
                          mobile: mobile,
                          suggestedAmount: _suggestedAmount(feeData),
                        ),
                        icon: const Icon(Icons.payments),
                        label: const Text("Add Payment"),
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
  }
}
