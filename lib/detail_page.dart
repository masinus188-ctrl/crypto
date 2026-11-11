import 'package:flutter/material.dart';

import 'crypto.dart';
import 'format.dart';
import 'price_chart.dart';
import 'price_history.dart';

const _blue = Color(0xFF0055D4);
const double _headerFont = 12; // ukuran teks Rank dan persentase (sama)

/// Halaman detail: tampil saat salah satu koin di daftar diketuk.
/// Semua harga di halaman ini ditampilkan dalam Dolar AS (USD).
class DetailPage extends StatefulWidget {
  final Crypto crypto;
  const DetailPage({super.key, required this.crypto});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  PricePeriod _period = PricePeriod.day1;
  List<PricePoint> _points = []; // harga dalam USD
  bool _loading = true;
  String? _error;

  // Simpan data tiap periode agar berpindah tab tidak memanggil API berulang
  final Map<PricePeriod, List<PricePoint>> _cache = {};

  // Kontrol untuk deretan tab periode yang bisa digeser, beserta tanda panah
  final ScrollController _tabScroll = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _tabScroll.addListener(_updateTabArrows);
    _load(_period);
  }

  @override
  void dispose() {
    _tabScroll.dispose();
    super.dispose();
  }

  // Tampilkan panah kanan/kiri hanya jika masih ada tab yang tersembunyi
  void _updateTabArrows() {
    if (!mounted || !_tabScroll.hasClients) return;
    final pos = _tabScroll.position;
    final left = pos.pixels > 4;
    final right = pos.pixels < pos.maxScrollExtent - 4;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _scrollTabs(bool toRight) {
    if (!_tabScroll.hasClients) return;
    final pos = _tabScroll.position;
    final target = (pos.pixels + (toRight ? 160 : -160))
        .clamp(0.0, pos.maxScrollExtent)
        .toDouble();
    _tabScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _load(PricePeriod period) async {
    setState(() {
      _period = period;
      _error = null;
    });

    final cached = _cache[period];
    if (cached != null) {
      setState(() {
        _points = cached;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final points = await fetchPriceHistory(
        widget.crypto.symbol,
        period,
        name: widget.crypto.name,
      );
      _cache[period] = points;
      // Abaikan hasil jika halaman sudah ditutup atau pengguna sudah pindah tab
      if (!mounted || _period != period) return;
      setState(() {
        _points = points;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _period != period) return;
      setState(() {
        _error = e is HistoryException ? e.message : 'Terjadi kesalahan: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.crypto;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('${c.name} (${c.symbol})'),
        backgroundColor: const Color(0xFFFFF3CD),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(c),
            const SizedBox(height: 16),
            _buildPeriodTabs(),
            const SizedBox(height: 12),
            SizedBox(height: 300, child: _buildChart()),
            const SizedBox(height: 8),
            _buildStats(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodTabs() {
    const divider = Color(0xFFDADCE0);
    final periods = PricePeriod.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Hitung ulang status panah setelah tata letak selesai
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateTabArrows());
        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: divider)),
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _tabScroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < periods.length; i++) ...[
                      _periodTab(periods[i]),
                      if (i < periods.length - 1)
                        Container(width: 1, height: 20, color: divider),
                    ],
                  ],
                ),
              ),
              if (_canScrollLeft) _tabArrow(toRight: false),
              if (_canScrollRight) _tabArrow(toRight: true),
            ],
          ),
        );
      },
    );
  }

  Widget _tabArrow({required bool toRight}) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: toRight ? null : 0,
      right: toRight ? 0 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _scrollTabs(toRight),
        child: Container(
          width: 40,
          alignment: toRight ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: toRight ? Alignment.centerLeft : Alignment.centerRight,
              end: toRight ? Alignment.centerRight : Alignment.centerLeft,
              colors: const [Color(0x00FFFFFF), Colors.white],
            ),
          ),
          child: Icon(
            toRight ? Icons.chevron_right : Icons.chevron_left,
            color: _blue,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _periodTab(PricePeriod p) {
    final selected = p == _period;
    return InkWell(
      onTap: () => _load(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? _blue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          p.label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? _blue : const Color(0xFF5F6368),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Crypto c) {
    // Harga terkini langsung dari CoinLore (USD), tanpa konversi
    final usd = double.tryParse(c.priceUsd);
    final price = usd != null ? formatUsd(usd) : c.priceUsd;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        border: Border.all(color: const Color(0xFFE6D59A), width: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris atas: Rank di kiri, persentase perubahan di kanan (ukuran sama)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rank ${c.rank}',
                style: const TextStyle(fontSize: _headerFont),
              ),
              _buildChange(),
            ],
          ),
          const SizedBox(height: 4),
          const Text('USD', style: TextStyle(fontSize: _headerFont)),
          // FittedBox mengecilkan teks otomatis jika angkanya panjang
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(price, style: const TextStyle(fontSize: 28)),
          ),
        ],
      ),
    );
  }

  // Persentase perubahan harga pada periode yang dipilih
  Widget _buildChange() {
    if (_points.length < 2) return const SizedBox.shrink();
    final first = _points.first.price;
    final last = _points.last.price;
    final pct = (last - first) / first * 100;
    return Text(
      formatPercent(pct),
      style: TextStyle(
        fontSize: _headerFont,
        color: pct >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
      ),
    );
  }

  Widget _buildChart() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => _load(_period),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    return PriceChart(points: _points, period: _period);
  }

  Widget _buildStats() {
    if (_points.length < 2) return const SizedBox.shrink();
    var hi = _points.first.price;
    var lo = hi;
    for (final p in _points) {
      if (p.price > hi) hi = p.price;
      if (p.price < lo) lo = p.price;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _stat('Tertinggi', formatUsdShort(hi)),
        _stat('Terendah', formatUsdShort(lo)),
        _stat('Awal periode', formatUsdShort(_points.first.price)),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
