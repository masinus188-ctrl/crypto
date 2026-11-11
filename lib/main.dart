import 'dart:async';

import 'package:flutter/material.dart';

import 'crypto.dart';
import 'detail_page.dart';
import 'format.dart';

void main() {
  runApp(const MyApp());
}

/// APLIKASI UTAMA
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto List',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const CryptoPage(),
    );
  }
}

/// HALAMAN DAFTAR: daftar koin yang diperbarui otomatis setiap 1 detik
class CryptoPage extends StatefulWidget {
  const CryptoPage({super.key});

  @override
  State<CryptoPage> createState() => _CryptoPageState();
}

class _CryptoPageState extends State<CryptoPage> with WidgetsBindingObserver {
  List<Crypto> _cryptos = [];
  bool _firstLoad = true; // true sampai data pertama selesai dimuat
  bool _fetching = false; // mencegah permintaan menumpuk
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _loadData());
  }

  // Hentikan refresh saat aplikasi di latar belakang, lanjutkan saat kembali
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
      _startTimer();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  Future<void> _loadData() async {
    // Lewati jika permintaan sebelumnya belum selesai
    // (CoinLore membatasi maksimal 1 permintaan per detik)
    if (_fetching) return;
    _fetching = true;
    try {
      final result = await fetchCryptos();
      if (!mounted) return;
      setState(() {
        _cryptos = result;
        _error = null;
        _firstLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Jika gagal saat refresh, data lama tetap ditampilkan
      setState(() {
        _error = 'Terjadi kesalahan: $e';
        _firstLoad = false;
      });
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_cryptos.isEmpty) {
      if (_firstLoad) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '$_error\n\nMencoba lagi otomatis...',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
    }
    return ListView.builder(
      itemCount: _cryptos.length,
      itemBuilder: (context, index) {
        final crypto = _cryptos[index];
        return CryptoItem(
          crypto: crypto,
          // Ketuk item -> buka halaman detail dengan grafik harga
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetailPage(crypto: crypto)),
          ),
        );
      },
    );
  }
}

/// WIDGET: satu baris item (Rank | Name + Symbol | USD + Harga)
class CryptoItem extends StatelessWidget {
  final Crypto crypto;
  final VoidCallback onTap;
  const CryptoItem({super.key, required this.crypto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 11, color: Colors.black87);
    const big = TextStyle(fontSize: 20, color: Colors.black);

    // Harga: koma untuk ribuan, titik untuk desimal (contoh 67,432.50)
    final usd = double.tryParse(crypto.priceUsd);
    final price = usd != null
        ? formatUsd(usd, withSymbol: false)
        : crypto.priceUsd;

    // Material + InkWell supaya ada efek ripple saat diketuk
    return Material(
      color: const Color(0xFFFFF3CD),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6D59A), width: 0.7),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rank', style: small),
                    Text('${crypto.rank}', style: big),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crypto.name,
                      style: small,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      crypto.symbol,
                      style: big,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('USD', style: small),
                    Text(
                      price,
                      style: big,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
