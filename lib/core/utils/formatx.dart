import 'package:intl/intl.dart';

/// Formatting helpers (currency in INR, dates, safe numeric parsing of API values
/// which often arrive as strings like "720.0000").
class Formatx {
  Formatx._();

  static final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final NumberFormat _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  static double toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static int toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().split('.').first) ?? fallback;
  }

  static String money(dynamic v) => _inr.format(toDouble(v));
  static String money2(dynamic v) => _inr2.format(toDouble(v));

  static String date(dynamic v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    return dt == null ? s : DateFormat('d MMM, h:mm a').format(dt.toLocal());
  }
}
