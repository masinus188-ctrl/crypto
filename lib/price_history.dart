import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Satu titik data pada grafik (waktu + harga penutupan dalam USD)
class PricePoint {
  final DateTime time;
  final double price;
  const PricePoint(this.time, this.price);
}

enum PricePeriod {
  day1('1HR', '1h', 24),
  day5('5HR', '1h', 120),
  month1('1BLN', '1h', 720),
  month6('6BLN', '1d', 180),
  ytd('YTD', '1d', 0), // dihitung otomatis dari 1 Januari
  year1('1TH', '1d', 365),
  year5('5TH', '1d', 1825),
  allTime('Maks', '1d', null);

  final String label;
  final String interval;
  final int? _count;

  const PricePeriod(this.label, this.interval, this._count);

  /// true jika datanya per jam (tooltip menampilkan jam)
  bool get hourly => interval == '1h';

  /// Waktu awal data dalam milidetik (epoch). 0 = dari data paling awal.
  int get startMs {
    final now = DateTime.now();
    if (this == PricePeriod.ytd) {
      final jan1 = DateTime(now.year, 1, 1);
      final minStart = now.subtract(const Duration(days: 2)); // minimal 2 titik
      return (jan1.isBefore(minStart) ? jan1 : minStart).millisecondsSinceEpoch;
    }
    if (_count == null) return 0;
    final step = hourly ? const Duration(hours: 1) : const Duration(days: 1);
    return now.subtract(step * _count!).millisecondsSinceEpoch;
  }
}

class HistoryException implements Exception {
  final String message;
  HistoryException(this.message);

  @override
  String toString() => message;
}

/// Kegagalan satu sumber data. [notFound] = koin memang tidak ada di sumber itu.
class _ProviderError implements Exception {
  final String detail;
  final bool notFound;
  _ProviderError(this.detail, {this.notFound = false});
}

class _Source {
  final String name;
  final Future<List<PricePoint>> Function(
    String symbol,
    String? name,
    PricePeriod period,
  )
  fetch;
  const _Source(this.name, this.fetch);
}

/// Mengurutkan sumber data, jika satu sumber diblokir/gagal, otomatis pindah ke sumber berikutnya.
final _sources = <_Source>[
  _Source('Binance', _fromBinance),
  _Source('Coinbase', _fromCoinbase),
  _Source('CoinGecko', _fromCoinGecko),
];

int _lastGood = 0;

/// CoinLore
Future<List<PricePoint>> fetchPriceHistory(
  String symbol,
  PricePeriod period, {
  String? name,
}) async {
  final sym = symbol.toUpperCase();
  final errors = <String>[];
  var allNotFound = true;

  for (var k = 0; k < _sources.length; k++) {
    final idx = (_lastGood + k) % _sources.length;
    final src = _sources[idx];
    try {
      final pts = await src.fetch(sym, name, period);
      if (pts.length >= 2) {
        _lastGood = idx;
        return _downsample(pts, 300);
      }
    } on _ProviderError catch (e) {
      if (!e.notFound) {
        allNotFound = false;
        errors.add('${src.name}: ${e.detail}');
      }
    } catch (e) {
      allNotFound = false;
      errors.add('${src.name}: ${_describe(e)}');
    }
  }

  if (allNotFound) {
    throw HistoryException('Data riwayat harga tidak tersedia untuk koin ini.');
  }
  // Rincian per sumber ditampilkan supaya penyebab kegagalan mudah dilacak
  throw HistoryException('Gagal memuat grafik.\n${errors.join('\n')}');
}

String _describe(Object e) {
  if (e is TimeoutException) return 'waktu habis';
  if (e is FormatException) return 'respons tidak valid (mungkin diblokir)';
  final s = e.toString();
  if (s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('HandshakeException')) {
    return 'tidak dapat terhubung';
  }
  return s.length > 70 ? '${s.substring(0, 70)}…' : s;
}

Future<dynamic> _getJson(Uri uri, {Set<int> notFound = const {404}}) async {
  final r = await http
      .get(uri, headers: const {'Accept': 'application/json'})
      .timeout(const Duration(seconds: 8));
  if (notFound.contains(r.statusCode)) {
    throw _ProviderError('tidak ada data', notFound: true);
  }
  if (r.statusCode != 200) {
    throw _ProviderError('kode ${r.statusCode}');
  }
  return jsonDecode(r.body);
}

// Binance
const _binanceHosts = ['api.binance.com', 'data-api.binance.vision'];
const _binancePage = 1000;

Future<List<PricePoint>> _fromBinance(
  String symbol,
  String? name,
  PricePeriod period,
) async {
  final points = <PricePoint>[];
  var start = period.startMs;

  for (var page = 0; page < 20; page++) {
    List<dynamic>? rows;
    _ProviderError? err;
    for (final host in _binanceHosts) {
      try {
        final data = await _getJson(
          Uri.https(host, '/api/v3/klines', {
            'symbol': '${symbol}USDT',
            'interval': period.interval,
            'startTime': '$start',
            'limit': '$_binancePage',
          }),
          notFound: const {400, 404}, // 400 = simbol tidak ada
        );
        rows = data as List<dynamic>;
        break;
      } on _ProviderError catch (e) {
        if (e.notFound) rethrow;
        err = e;
      } catch (e) {
        err = _ProviderError(_describe(e));
      }
    }
    if (rows == null) throw err ?? _ProviderError('gagal');

    for (final row in rows) {
      final list = row as List<dynamic>;
      final ms = (list[0] as num).toInt();
      final close = double.tryParse(list[4].toString()) ?? 0;
      if (close > 0) {
        points.add(PricePoint(DateTime.fromMillisecondsSinceEpoch(ms), close));
      }
    }
    if (rows.length < _binancePage) break;
    start = ((rows.last as List<dynamic>)[0] as num).toInt() + 1;
  }
  return points;
}

// Coinbase
String _iso(DateTime t) => '${t.toUtc().toIso8601String().split('.').first}Z';

Future<List<PricePoint>> _fromCoinbase(
  String symbol,
  String? name,
  PricePeriod period,
) async {
  final gran = period.hourly ? 3600 : 86400;
  final window = Duration(seconds: gran * 299);
  final now = DateTime.now().toUtc();
  var cursor = period.startMs == 0
      ? DateTime.utc(2015, 1, 1)
      : DateTime.fromMillisecondsSinceEpoch(period.startMs, isUtc: true);

  final byTime = <int, double>{};
  for (var page = 0; page < 30 && cursor.isBefore(now); page++) {
    var end = cursor.add(window);
    if (end.isAfter(now)) end = now;

    final data = await _getJson(
      Uri.https('api.exchange.coinbase.com', '/products/$symbol-USD/candles', {
        'granularity': '$gran',
        'start': _iso(cursor),
        'end': _iso(end),
      }),
    );
    // Format baris: [waktu(detik), low, high, open, close, volume]
    for (final row in data as List<dynamic>) {
      final r = row as List<dynamic>;
      final close = (r[4] as num).toDouble();
      if (close > 0) byTime[(r[0] as num).toInt()] = close;
    }
    cursor = end;
  }

  final times = byTime.keys.toList()..sort();
  return [
    for (final t in times)
      PricePoint(DateTime.fromMillisecondsSinceEpoch(t * 1000), byTime[t]!),
  ];
}

// Coingecko
final Map<String, String> _geckoIds = {};

Future<String> _geckoId(String symbol, String? name) async {
  final key = '$symbol|${name ?? ''}';
  final cached = _geckoIds[key];
  if (cached != null) return cached;

  final data = await _getJson(
    Uri.https('api.coingecko.com', '/api/v3/search', {'query': symbol}),
  ) as Map<String, dynamic>;

  String? exact;
  String? bySymbol;
  for (final c in data['coins'] as List<dynamic>) {
    final m = c as Map<String, dynamic>;
    if ((m['symbol'] as String).toUpperCase() != symbol) continue;
    bySymbol ??= m['id'] as String;
    if (name != null &&
        (m['name'] as String).toLowerCase() == name.toLowerCase()) {
      exact = m['id'] as String;
      break;
    }
  }
  final id = exact ?? bySymbol;
  if (id == null) throw _ProviderError('tidak ada data', notFound: true);
  return _geckoIds[key] = id;
}

int _geckoDays(PricePeriod p) {
  switch (p) {
    case PricePeriod.day1:
      return 1;
    case PricePeriod.day5:
      return 5;
    case PricePeriod.month1:
      return 30;
    case PricePeriod.month6:
      return 180;
    case PricePeriod.ytd:
      final now = DateTime.now();
      final d = now.difference(DateTime(now.year, 1, 1)).inDays;
      return d < 2 ? 2 : (d > 365 ? 365 : d);
    case PricePeriod.year1:
    case PricePeriod.year5:
    case PricePeriod.allTime:
      return 365;
  }
}

Future<List<PricePoint>> _fromCoinGecko(
  String symbol,
  String? name,
  PricePeriod period,
) async {
  final id = await _geckoId(symbol, name);
  final data = await _getJson(
    Uri.https('api.coingecko.com', '/api/v3/coins/$id/market_chart', {
      'vs_currency': 'usd',
      'days': '${_geckoDays(period)}',
    }),
  ) as Map<String, dynamic>;

  final points = <PricePoint>[];
  for (final row in data['prices'] as List<dynamic>) {
    final r = row as List<dynamic>;
    final price = (r[1] as num?)?.toDouble() ?? 0;
    if (price > 0) {
      points.add(
        PricePoint(
          DateTime.fromMillisecondsSinceEpoch((r[0] as num).toInt()),
          price,
        ),
      );
    }
  }
  return points;
}

/// Mengurangi jumlah titik (untuk periode panjang yang bisa ribuan titik)
List<PricePoint> _downsample(List<PricePoint> pts, int maxPoints) {
  if (pts.length <= maxPoints) return pts;
  final step = pts.length / maxPoints;
  final result = <PricePoint>[];
  for (var i = 0; i < maxPoints; i++) {
    result.add(pts[(i * step).floor()]);
  }
  result.add(pts.last);
  return result;
}
