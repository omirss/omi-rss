import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/glass_container.dart';
import '../glass_theme.dart';
import '../../providers/market_provider.dart';

enum ChartType {
  line,
  candlestick,
  area,
  bar,
}

enum ChartInterval {
  minute1('1m', Duration(minutes: 1)),
  minute5('5m', Duration(minutes: 5)),
  minute15('15m', Duration(minutes: 15)),
  hour1('1h', Duration(hours: 1)),
  day1('1d', Duration(days: 1)),
  week1('1w', Duration(days: 7)),
  month1('1M', Duration(days: 30));

  final String label;
  final Duration duration;
  
  const ChartInterval(this.label, this.duration);
}

class MarketChart extends ConsumerStatefulWidget {
  final String symbol;
  final ChartType chartType;
  final ChartInterval interval;
  final bool showVolume;
  final bool showIndicators;
  final double height;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  
  const MarketChart({
    super.key,
    required this.symbol,
    this.chartType = ChartType.line,
    this.interval = ChartInterval.day1,
    this.showVolume = true,
    this.showIndicators = false,
    this.height = 300,
    this.padding,
    this.onTap,
  });

  @override
  ConsumerState<MarketChart> createState() => _MarketChartState();
}

class _MarketChartState extends ConsumerState<MarketChart> {
  List<FlSpot> _priceData = [];
  List<FlSpot> _volumeData = [];
  List<CandleData> _candleData = [];
  double _minPrice = 0;
  double _maxPrice = 0;
  double _maxVolume = 0;
  
  @override
  void initState() {
    super.initState();
    _loadChartData();
  }
  
  @override
  void didUpdateWidget(MarketChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol ||
        oldWidget.interval != widget.interval) {
      _loadChartData();
    }
  }
  
  Future<void> _loadChartData() async {
    // In a real implementation, this would fetch from market service
    // For now, generate sample data
    final now = DateTime.now();
    final dataPoints = 50;
    _priceData = [];
    _volumeData = [];
    _candleData = [];
    
    double basePrice = 100;
    _minPrice = double.infinity;
    _maxPrice = double.negativeInfinity;
    _maxVolume = 0;
    
    for (int i = 0; i < dataPoints; i++) {
      final price = basePrice + (i * 0.5) + (5 * (i % 2 == 0 ? 1 : -1));
      final volume = 1000000 + (500000 * (i % 3));
      
      _priceData.add(FlSpot(i.toDouble(), price));
      _volumeData.add(FlSpot(i.toDouble(), volume / 1000000)); // Scale to millions
      
      // Generate candle data
      final open = price - 2 + (4 * (i % 2));
      final close = price;
      final high = price + 2;
      final low = price - 3;
      
      _candleData.add(CandleData(
        time: now.subtract(Duration(days: dataPoints - i)),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ));
      
      _minPrice = [_minPrice, low].reduce((a, b) => a < b ? a : b);
      _maxPrice = [_maxPrice, high].reduce((a, b) => a > b ? a : b);
      _maxVolume = [_maxVolume, volume].reduce((a, b) => a > b ? a : b);
    }
    
    if (mounted) {
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: widget.padding ?? const EdgeInsets.all(16),
      onTap: widget.onTap,
      child: Column(
        children: [
          _buildChartHeader(),
          const SizedBox(height: 16),
          SizedBox(
            height: widget.height,
            child: _buildChart(),
          ),
          if (widget.showVolume) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: _buildVolumeChart(),
            ),
          ],
          if (widget.showIndicators) ...[
            const SizedBox(height: 16),
            _buildIndicators(),
          ],
        ],
      ),
    );
  }
  
  Widget _buildChartHeader() {
    final quote = ref.watch(marketQuoteProvider(widget.symbol));
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.symbol,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (quote != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '\$${quote.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: quote.changePercent >= 0
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${quote.changePercent >= 0 ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: quote.changePercent >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        Row(
          children: ChartInterval.values.map((interval) {
            final isSelected = interval == widget.interval;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                onTap: () {
                  // Handle interval change
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    interval.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : Colors.white60,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
  
  Widget _buildChart() {
    switch (widget.chartType) {
      case ChartType.line:
        return _buildLineChart();
      case ChartType.candlestick:
        return _buildCandlestickChart();
      case ChartType.area:
        return _buildAreaChart();
      case ChartType.bar:
        return _buildBarChart();
    }
  }
  
  Widget _buildLineChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (_maxPrice - _minPrice) / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              show: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '\$${value.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: _priceData.length.toDouble() - 1,
        minY: _minPrice * 0.98,
        maxY: _maxPrice * 1.02,
        lineBarsData: [
          LineChartBarData(
            spots: _priceData,
            isCurved: true,
            color: Theme.of(context).primaryColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).primaryColor.withOpacity(0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.black87,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '\$${spot.y.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
  
  Widget _buildAreaChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (_maxPrice - _minPrice) / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              show: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '\$${value.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: _priceData.length.toDouble() - 1,
        minY: _minPrice * 0.98,
        maxY: _maxPrice * 1.02,
        lineBarsData: [
          LineChartBarData(
            spots: _priceData,
            isCurved: true,
            color: Theme.of(context).primaryColor,
            barWidth: 0,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.4),
                  Theme.of(context).primaryColor.withOpacity(0.1),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (_maxPrice - _minPrice) / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              show: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '\$${value.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(show: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: _minPrice * 0.98,
        maxY: _maxPrice * 1.02,
        barGroups: _priceData.map((spot) {
          final isPositive = spot.y > (_priceData.isNotEmpty ? _priceData.first.y : 0);
          return BarChartGroupData(
            x: spot.x.toInt(),
            barRods: [
              BarChartRodData(
                toY: spot.y,
                color: isPositive ? Colors.green : Colors.red,
                width: 2,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildCandlestickChart() {
    return CustomPaint(
      painter: CandlestickPainter(
        candles: _candleData,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
      ),
      child: Container(),
    );
  }
  
  Widget _buildVolumeChart() {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: _volumeData.map((spot) {
          return BarChartGroupData(
            x: spot.x.toInt(),
            barRods: [
              BarChartRodData(
                toY: spot.y,
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildIndicators() {
    final indicators = ref.watch(technicalIndicatorsProvider(widget.symbol));
    
    if (indicators == null) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Technical Indicators',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildIndicatorChip('RSI', indicators['rsi']?.toStringAsFixed(1) ?? '-'),
            _buildIndicatorChip('SMA 20', '\$${indicators['sma20']?.toStringAsFixed(2) ?? '-'}'),
            _buildIndicatorChip('SMA 50', '\$${indicators['sma50']?.toStringAsFixed(2) ?? '-'}'),
            _buildIndicatorChip('MACD', indicators['macd']?.toStringAsFixed(2) ?? '-'),
            _buildIndicatorChip('Volume', _formatVolume(indicators['volume'] ?? 0)),
          ],
        ),
      ],
    );
  }
  
  Widget _buildIndicatorChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatVolume(double volume) {
    if (volume >= 1000000000) {
      return '${(volume / 1000000000).toStringAsFixed(1)}B';
    } else if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(1)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(1)}K';
    }
    return volume.toStringAsFixed(0);
  }
}

// Candle data model
class CandleData {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  
  CandleData({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });
  
  bool get isGreen => close >= open;
}

// Custom painter for candlestick chart
class CandlestickPainter extends CustomPainter {
  final List<CandleData> candles;
  final double minPrice;
  final double maxPrice;
  
  CandlestickPainter({
    required this.candles,
    required this.minPrice,
    required this.maxPrice,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    
    final priceRange = maxPrice - minPrice;
    final candleWidth = size.width / candles.length * 0.8;
    final spacing = size.width / candles.length * 0.2;
    
    for (int i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final x = i * (candleWidth + spacing) + spacing / 2;
      
      // Calculate Y positions
      final highY = (1 - (candle.high - minPrice) / priceRange) * size.height;
      final lowY = (1 - (candle.low - minPrice) / priceRange) * size.height;
      final openY = (1 - (candle.open - minPrice) / priceRange) * size.height;
      final closeY = (1 - (candle.close - minPrice) / priceRange) * size.height;
      
      final paint = Paint()
        ..color = candle.isGreen ? Colors.green : Colors.red
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      
      // Draw high-low line
      canvas.drawLine(
        Offset(x + candleWidth / 2, highY),
        Offset(x + candleWidth / 2, lowY),
        paint,
      );
      
      // Draw open-close body
      paint.style = PaintingStyle.fill;
      paint.color = candle.isGreen 
          ? Colors.green.withOpacity(0.8)
          : Colors.red.withOpacity(0.8);
      
      canvas.drawRect(
        Rect.fromLTRB(
          x,
          candle.isGreen ? closeY : openY,
          x + candleWidth,
          candle.isGreen ? openY : closeY,
        ),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
           oldDelegate.minPrice != minPrice ||
           oldDelegate.maxPrice != maxPrice;
  }
}