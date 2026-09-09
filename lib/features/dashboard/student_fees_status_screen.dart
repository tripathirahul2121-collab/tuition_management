import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StudentFeesStatusScreen extends StatelessWidget {
  const StudentFeesStatusScreen({super.key});

  String _money(num value) {
    final amount = value.toDouble();
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount.toStringAsFixed(2);
  }

  DateTime _paymentDate(dynamic payment) {
    if (payment is! Map<String, dynamic>) return DateTime(2000);
    final date = payment["date"];
    if (date is Timestamp) return date.toDate();
    return DateTime(2000);
  }

  double _totalPaid(List<dynamic> payments) {
    return payments.fold<double>(0, (total, payment) {
      if (payment is! Map<String, dynamic>) return total;
      return total + ((payment["amount"] ?? 0) as num).toDouble();
    });
  }

  double _paidThisMonth(List<dynamic> payments) {
    final now = DateTime.now();

    return payments.fold<double>(0, (total, payment) {
      if (payment is! Map<String, dynamic>) return total;
      final date = _paymentDate(payment);

      if (date.month != now.month || date.year != now.year) return total;
      return total + ((payment["amount"] ?? 0) as num).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    final mobile = userData["mobile"]?.toString() ?? "";
    final studentClass = userData["class"]?.toString() ?? "";

    return Scaffold(
      appBar: AppBar(title: const Text("Fees Status")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection("fees")
            .doc("Class-$studentClass")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists) {
            return const Center(child: Text("Fees not set yet"));
          }

          final feeData = snapshot.data!.data() ?? {};
          final mode = feeData["mode"]?.toString() ?? "monthly";
          final monthlyFee = ((feeData["monthlyFee"] ?? 0) as num).toDouble();
          final annualFee = ((feeData["totalAnnualFee"] ?? 0) as num)
              .toDouble();
          final installment = ((feeData["installment"] ?? 0) as num).toDouble();

          final rawStudents = feeData["students"];
          final students = rawStudents is Map<String, dynamic>
              ? rawStudents
              : <String, dynamic>{};
          final studentFee = students[mobile];
          final payments = studentFee is Map<String, dynamic>
              ? List<dynamic>.from(studentFee["payments"] ?? [])
              : <dynamic>[];

          payments.sort((a, b) => _paymentDate(b).compareTo(_paymentDate(a)));

          final totalPaid = _totalPaid(payments);
          final paidThisMonth = _paidThisMonth(payments);
          final expectedThisMonth = mode == "annual" ? installment : monthlyFee;
          final balance = mode == "annual"
              ? (annualFee - totalPaid).clamp(0, double.infinity)
              : (expectedThisMonth - paidThisMonth).clamp(0, double.infinity);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Fees Status",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _row(
                        mode == "annual" ? "Annual Fee" : "Monthly Fee",
                        "Rs ${_money(mode == "annual" ? annualFee : monthlyFee)}",
                      ),
                      if (mode == "annual")
                        _row(
                          "Monthly Installment",
                          "Rs ${_money(installment)}",
                        ),
                      _row("Paid This Month", "Rs ${_money(paidThisMonth)}"),
                      _row("Total Paid", "Rs ${_money(totalPaid)}"),
                      _row("Balance", "Rs ${_money(balance)}"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Payment History",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (payments.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("No payment recorded yet"),
                  ),
                )
              else
                ...payments.map((payment) {
                  final amount = payment["amount"] as num? ?? 0;
                  final date = _paymentDate(payment);

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: Text("Rs ${_money(amount)}"),
                      subtitle: Text(DateFormat("dd MMM yyyy").format(date)),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
