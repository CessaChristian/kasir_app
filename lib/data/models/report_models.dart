part of '../app_database.dart';

// ============================================================
// Models laporan — dipindah dari app_database.dart agar file
// tidak melebihi 1000 baris. Menggunakan `part of` supaya
// tetap bisa akses tipe Drift (Transaction, Expense, dll.)
// tanpa circular import.
// ============================================================

class ReportSummary {
  final DateTime date;
  final int totalOrders;
  final int totalIncome;
  final int totalExpenses;
  final int cashOrders;
  final int cashTotal;
  final int qrisOrders;
  final int qrisTotal;
  final int dineInOrders;
  final int takeAwayOrders;
  final int deliveryOrders;
  final List<Transaction> transactions;
  final List<TopProduct> topProducts;

  int get netIncome => totalIncome - totalExpenses;

  ReportSummary({
    required this.date,
    required this.totalOrders,
    required this.totalIncome,
    required this.totalExpenses,
    required this.cashOrders,
    required this.cashTotal,
    required this.qrisOrders,
    required this.qrisTotal,
    required this.dineInOrders,
    required this.takeAwayOrders,
    required this.deliveryOrders,
    required this.transactions,
    required this.topProducts,
  });
}

class ShiftInfo {
  final String shiftId;
  final DateTime startAt;
  final DateTime? endAt;
  final int transactionCount;
  final int totalIncome;
  final int totalExpenses;

  int get netIncome => totalIncome - totalExpenses;

  ShiftInfo({
    required this.shiftId,
    required this.startAt,
    this.endAt,
    required this.transactionCount,
    required this.totalIncome,
    required this.totalExpenses,
  });
}

class EmployeeReportSummary {
  final String userId;
  final String username;
  final int totalTransactions;
  final int totalIncome;
  final int totalExpenses;
  final int cashOrders;
  final int cashTotal;
  final int qrisOrders;
  final int qrisTotal;
  final List<ShiftInfo> shifts;
  final List<Transaction> transactions;
  final List<TopProduct> topProducts;

  int get netIncome => totalIncome - totalExpenses;

  EmployeeReportSummary({
    required this.userId,
    required this.username,
    required this.totalTransactions,
    required this.totalIncome,
    required this.totalExpenses,
    required this.cashOrders,
    required this.cashTotal,
    required this.qrisOrders,
    required this.qrisTotal,
    required this.shifts,
    required this.transactions,
    required this.topProducts,
  });
}

class DailyTrend {
  final DateTime date;
  final int orders;
  final int income;

  DailyTrend({
    required this.date,
    required this.orders,
    required this.income,
  });
}

class ExpenseEntry {
  final Expense expense;
  final String username;

  ExpenseEntry({required this.expense, required this.username});
}
