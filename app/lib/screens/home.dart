/// Home - the 30-day forecast, its uncertainty band, and the predicted risk window.
///
/// The band is the point of this screen. A single projected line would imply a
/// precision the model does not have; showing P10-P90 is what lets the customer see
/// that the shortfall is *plausible* rather than certain, and it is the same P10 the
/// savings plan is computed from.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.forecast, required this.profile});

  final Map<String, dynamic> forecast;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final path = (forecast['path'] as List).cast<Map<String, dynamic>>();
    final balance = (forecast['balance_today'] as num).toDouble();
    final floor = (forecast['safety_floor'] as num).toDouble();
    final risk = forecast['risk_window'] as Map<String, dynamic>?;
    final narrative = forecast['narrative'] as Map<String, dynamic>;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('বর্তমান ব্যালেন্স',
                  style: TextStyle(fontSize: 14, color: C.muted)),
              const SizedBox(height: 6),
              Text('৳${bnNum(balance)}',
                  style: const TextStyle(
                      fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 6),
              Text(
                'নিরাপত্তা সীমা ৳${bnNum(floor)}  •  ${bnDate(forecast['as_of'] as String)} পর্যন্ত হিসাব',
                style: const TextStyle(fontSize: 13, color: C.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (risk != null)
          StatusNote(
            icon: Icons.warning_amber_rounded,
            color: C.risk,
            background: C.riskBg,
            text: narrative['risk']['bn'] as String,
          )
        else
          StatusNote(
            icon: Icons.check_circle_outline,
            color: C.safe,
            background: C.safeBg,
            text: narrative['risk']['bn'] as String,
          ),
        const SizedBox(height: 14),
        Panel(
          title: 'আগামী ৩০ দিনের পূর্বাভাস',
          subtitle: 'ছায়া অংশ = সম্ভাব্য সীমা (P10–P90)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 230,
                child: _ForecastChart(path: path, floor: floor, risk: risk),
              ),
              const SizedBox(height: 14),
              const _Legend(),
              const SizedBox(height: 14),
              Text(narrative['forecast']['bn'] as String,
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
              const Divider(height: 28),
              WhyBlock(reasons: (forecast['reasons'] as List?) ?? const []),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: 'গত ৩০ দিনে',
          child: Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'মোট আয়',
                  value: '৳${bnNum((profile['inflow_last_30d'] as num).toDouble())}',
                  color: C.safe,
                ),
              ),
              Container(width: 1, height: 44, color: C.line),
              Expanded(
                child: _Stat(
                  label: 'মোট খরচ',
                  value: '৳${bnNum((profile['outflow_last_30d'] as num).toDouble())}',
                  color: C.risk,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          forecast['disclaimer'] as String? ?? '',
          style: const TextStyle(fontSize: 12, color: C.muted, height: 1.5),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: C.muted)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: const [
        _LegendItem(color: C.brand, label: 'সম্ভাব্য ব্যালেন্স'),
        _LegendItem(color: C.band, label: 'অনিশ্চয়তার সীমা'),
        _LegendItem(color: C.risk, label: 'নিরাপত্তা সীমা'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5, color: C.muted)),
      ],
    );
  }
}

class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.path, required this.floor, this.risk});

  final List<Map<String, dynamic>> path;
  final double floor;
  final Map<String, dynamic>? risk;

  double _v(Map<String, dynamic> p, String k) => (p[k] as num).toDouble();

  @override
  Widget build(BuildContext context) {
    final lows = [for (var i = 0; i < path.length; i++) FlSpot(i.toDouble(), _v(path[i], 'low'))];
    final highs = [for (var i = 0; i < path.length; i++) FlSpot(i.toDouble(), _v(path[i], 'high'))];
    final mids = [for (var i = 0; i < path.length; i++) FlSpot(i.toDouble(), _v(path[i], 'expected'))];

    final allY = [
      for (final p in path) ...[_v(p, 'low'), _v(p, 'high'), _v(p, 'expected')],
      floor,
    ];
    var minY = allY.reduce((a, b) => a < b ? a : b);
    var maxY = allY.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.12).clamp(500.0, double.infinity);
    minY -= pad;
    maxY += pad;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: C.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, _) => Text(
                '${bnNum(v / 1000)}k',
                style: const TextStyle(fontSize: 10.5, color: C.muted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 7,
              reservedSize: 30,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= path.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(bnDate(path[i]['date'] as String),
                      style: const TextStyle(fontSize: 10, color: C.muted)),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: floor,
            color: C.risk,
            strokeWidth: 1.5,
            dashArray: [6, 4],
          ),
        ]),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                if (s.barIndex == 2)
                  LineTooltipItem(
                    '${bnDate(path[s.x.toInt()]['date'] as String)}\n৳${bnNum(s.y)}',
                    const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  )
                else
                  null,
            ],
          ),
        ),
        // The P10-P90 band: fl_chart fills between two series, so the bounds are
        // drawn as hairlines and the shading is declared here.
        betweenBarsData: [
          BetweenBarsData(fromIndex: 0, toIndex: 1, color: C.band),
        ],
        lineBarsData: [
          LineChartBarData(
            spots: lows,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 1,
            dotData: const FlDotData(show: false),
            color: C.brand.withValues(alpha: 0.35),
          ),
          LineChartBarData(
            spots: highs,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 1,
            dotData: const FlDotData(show: false),
            color: C.brand.withValues(alpha: 0.35),
          ),
          // expected path
          LineChartBarData(
            spots: mids,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 3,
            color: C.brand,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
