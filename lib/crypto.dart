import 'dart:convert';

import 'package:http/http.dart' as http;

/// MODEL: satu data cryptocurrency dari API CoinLore
class Crypto {
  final int rank;
  final String name;
  final String symbol;
  final String priceUsd;

  Crypto({
    required this.rank,
    required this.name,
    required this.symbol,
    required this.priceUsd,
  });

  factory Crypto.fromJson(Map<String, dynamic> json) {
    return Crypto(
      rank: int.tryParse(json['rank'].toString()) ?? 0,
      name: json['name'].toString(),
      symbol: json['symbol'].toString(),
      priceUsd: json['price_usd'].toString(),
    );
  }
}

/// SERVICE: mengambil daftar koin dari API CoinLore
Future<List<Crypto>> fetchCryptos() async {
  final response = await http.get(
    Uri.parse('https://api.coinlore.net/api/tickers/'),
  );

  if (response.statusCode == 200) {
    final Map<String, dynamic> body = jsonDecode(response.body);
    final List<dynamic> data = body['data'];
    return data
        .map((item) => Crypto.fromJson(item as Map<String, dynamic>))
        .toList();
  } else {
    throw Exception('Gagal memuat data (kode ${response.statusCode})');
  }
}
