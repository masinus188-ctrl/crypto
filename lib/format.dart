import 'price_history.dart';

const _bulan = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// Angka format USD: koma sebagai pemisah ribuan, titik sebagai desimal
String _num(double v, int decimals) {
  final parts = v.toStringAsFixed(decimals).split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return decimals == 0 ? intPart : '$intPart.${parts[1]}';
}

/// Jumlah desimal menyesuaikan besar harga (koin murah butuh lebih banyak desimal)
int _decimals(double p) {
  if (p >= 1) return 2;
  if (p >= 0.01) return 4;
  if (p >= 0.0001) return 6;
  return 8;
}

/// Contoh: 67432.5 -> "$67,432.50"  (withSymbol: false -> "67,432.50")
String formatUsd(double p, {bool withSymbol = true}) =>
    '${withSymbol ? '\$' : ''}${_num(p, _decimals(p))}';

/// Versi singkat untuk ruang sempit (label sumbu, ringkasan).
/// Contoh: 67432.5 -> "$67,432.50"   |   2500000000 -> "$2.50 B"
String formatUsdShort(double p, {bool withPrefix = true}) {
  final pre = withPrefix ? '\$' : '';
  if (p >= 1e12) return '$pre${_num(p / 1e12, 2)} T';
  if (p >= 1e9) return '$pre${_num(p / 1e9, 2)} B';
  if (p >= 1e6) return '$pre${_num(p / 1e6, 2)} M';
  return '$pre${_num(p, _decimals(p))}';
}

/// Contoh: 2.126 -> "+2.13%"
String formatPercent(double pct) =>
    '${pct >= 0 ? '+' : '-'}${_num(pct.abs(), 2)}%';

/// Label singkat untuk sumbu X (menyesuaikan periode)
String formatAxisDate(DateTime t, PricePeriod period) {
  switch (period) {
    case PricePeriod.day1:
      return '${_two(t.hour)}:${_two(t.minute)}';
    case PricePeriod.day5:
    case PricePeriod.month1:
      return '${t.day} ${_bulan[t.month - 1]}';
    case PricePeriod.month6:
    case PricePeriod.ytd:
    case PricePeriod.year1:
      return '${_bulan[t.month - 1]} ${_two(t.year % 100)}';
    case PricePeriod.year5:
    case PricePeriod.allTime:
      return '${t.year}';
  }
}

/// Tanggal lengkap untuk tooltip saat grafik disentuh
String formatFullDate(DateTime t, PricePeriod period) {
  final date = '${t.day} ${_bulan[t.month - 1]} ${t.year}';
  if (period.hourly) {
    return '$date, ${_two(t.hour)}:${_two(t.minute)}';
  }
  return date;
}
