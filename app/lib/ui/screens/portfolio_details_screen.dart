import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/portfolio.dart';
import '../../providers/portfolio_provider.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_dialog.dart';
import '../animations/loading_animation.dart';

/// Detailed portfolio view screen
class PortfolioDetailsScreen extends ConsumerStatefulWidget {
  final Portfolio portfolio;
  
  const PortfolioDetailsScreen({
    super.key,
    required this.portfolio,
  });
  
  @override
  ConsumerState<PortfolioDetailsScreen> createState() => _PortfolioDetailsScreenState();
}

class _PortfolioDetailsScreenState extends ConsumerState<PortfolioDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedTimeRange = '1D';
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final portfolioStream = ref.watch(portfolioStreamProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.portfolio.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editPortfolio,
            tooltip: 'Edit Portfolio',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _sharePortfolio,
            tooltip: 'Share',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Refresh Prices'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Export Data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('Delete Portfolio', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<Portfolio>(
        stream: portfolioStream,
        initialData: widget.portfolio,
        builder: (context, snapshot) {
          final portfolio = snapshot.data ?? widget.portfolio;
          
          return Column(
            children: [
              // Portfolio summary
              _buildPortfolioSummary(portfolio, theme),
              
              // Time range selector
              _buildTimeRangeSelector(theme),
              
              // Chart
              Expanded(
                flex: 2,
                child: _buildPerformanceChart(portfolio, theme),
              ),
              
              // Tabs
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Holdings'),
                  Tab(text: 'Performance'),
                  Tab(text: 'Transactions'),
                  Tab(text: 'Analytics'),
                ],
                indicatorColor: theme.accentColor,
              ),
              
              // Tab content
              Expanded(
                flex: 3,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildHoldingsTab(portfolio, theme),
                    _buildPerformanceTab(portfolio, theme),
                    _buildTransactionsTab(portfolio, theme),
                    _buildAnalyticsTab(portfolio, theme),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildPortfolioSummary(Portfolio portfolio, GlassThemeData theme) {
    final isPositive = portfolio.totalGainLoss >= 0;
    final isDayPositive = portfolio.dayChange >= 0;
    
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Total value
          Text(
            '\$${_formatCurrency(portfolio.totalValue)}',
            style: theme.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // Changes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Day change
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDayPositive ? Colors.green : Colors.red).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDayPositive ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: isDayPositive ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isDayPositive ? '+' : ''}\$${_formatCurrency(portfolio.dayChange.abs())}',
                      style: TextStyle(
                        color: isDayPositive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${isDayPositive ? '+' : ''}${portfolio.dayChangePercent.toStringAsFixed(2)}%)',
                      style: TextStyle(
                        color: isDayPositive ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Total gain/loss
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total: ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${isPositive ? '+' : ''}\$${_formatCurrency(portfolio.totalGainLoss.abs())}',
                      style: TextStyle(
                        color: isPositive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY();
  }
  
  Widget _buildTimeRangeSelector(GlassThemeData theme) {
    final ranges = ['1D', '1W', '1M', '3M', '1Y', 'ALL'];
    
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: ranges.length,
        itemBuilder: (context, index) {
          final range = ranges[index];
          final isSelected = range == _selectedTimeRange;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GlassButton(
              text: range,
              onPressed: () => setState(() => _selectedTimeRange = range),
              variant: isSelected 
                  ? GlassButtonVariant.elevated 
                  : GlassButtonVariant.text,
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildPerformanceChart(Portfolio portfolio, GlassThemeData theme) {
    // Generate sample data based on time range
    final spots = _generateChartData(portfolio);
    final isPositive = portfolio.totalGainLoss >= 0;
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.white.withOpacity(0.1),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: spots.length > 10 ? spots.length / 5 : 1,
                getTitlesWidget: (value, meta) {
                  return Text(
                    _getChartLabel(value.toInt()),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '\$${_formatShortCurrency(value)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: isPositive ? Colors.green : Colors.red,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    (isPositive ? Colors.green : Colors.red).withOpacity(0.3),
                    (isPositive ? Colors.green : Colors.red).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: Colors.black.withOpacity(0.8),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '\$${_formatCurrency(spot.y)}',
                    const TextStyle(color: Colors.white),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHoldingsTab(Portfolio portfolio, GlassThemeData theme) {
    if (portfolio.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No holdings yet',
              style: theme.bodyLarge.copyWith(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: portfolio.items.length,
      itemBuilder: (context, index) {
        final item = portfolio.items[index];
        return _buildHoldingCard(item, theme)
            .animate(delay: (index * 100).ms)
            .fadeIn()
            .slideX();
      },
    );
  }
  
  Widget _buildHoldingCard(PortfolioItem item, GlassThemeData theme) {
    final isPositive = item.gainLoss >= 0;
    final isDayPositive = item.dayChange >= 0;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: () => _showItemActions(item),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                // Symbol icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      item.symbol.substring(0, min(3, item.symbol.length)),
                      style: theme.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Name and info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.symbol,
                        style: theme.titleMedium,
                      ),
                      Text(
                        item.name,
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                
                // Current price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${item.currentPrice.toStringAsFixed(2)}',
                      style: theme.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDayPositive ? Icons.arrow_upward : Icons.arrow_downward,
                          color: isDayPositive ? Colors.green : Colors.red,
                          size: 14,
                        ),
                        Text(
                          '${isDayPositive ? '+' : ''}${item.dayChangePercent.toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: isDayPositive ? Colors.green : Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Holdings info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn(
                  'Quantity',
                  item.quantity.toStringAsFixed(2),
                  theme,
                ),
                _buildInfoColumn(
                  'Avg Cost',
                  '\$${item.averageCost.toStringAsFixed(2)}',
                  theme,
                ),
                _buildInfoColumn(
                  'Total Value',
                  '\$${_formatCurrency(item.totalValue)}',
                  theme,
                ),
                _buildInfoColumn(
                  'Gain/Loss',
                  '${isPositive ? '+' : ''}\$${_formatCurrency(item.gainLoss.abs())}',
                  theme,
                  valueColor: isPositive ? Colors.green : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoColumn(
    String label,
    String value,
    GlassThemeData theme, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.bodySmall.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.bodyMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
  
  Widget _buildPerformanceTab(Portfolio portfolio, GlassThemeData theme) {
    return FutureBuilder<PortfolioPerformance>(
      future: ref.read(portfolioPerformanceProvider(portfolio.id).future),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: LoadingAnimation());
        }
        
        final performance = snapshot.data!;
        
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Performance metrics
            _buildPerformanceMetrics(performance, theme),
            
            const SizedBox(height: 24),
            
            // Asset allocation
            Text('Asset Allocation', style: theme.titleLarge),
            const SizedBox(height: 16),
            _buildAllocationChart(performance.assetAllocation, theme),
            
            const SizedBox(height: 24),
            
            // Sector allocation
            if (performance.sectorAllocation.isNotEmpty) ...[
              Text('Sector Allocation', style: theme.titleLarge),
              const SizedBox(height: 16),
              _buildAllocationChart(performance.sectorAllocation, theme),
            ],
          ],
        );
      },
    );
  }
  
  Widget _buildPerformanceMetrics(PortfolioPerformance performance, GlassThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMetricRow('1 Day', performance.dayChange, performance.dayChangePercent, theme),
          _buildMetricRow('1 Week', performance.weekChange, performance.weekChangePercent, theme),
          _buildMetricRow('1 Month', performance.monthChange, performance.monthChangePercent, theme),
          _buildMetricRow('1 Year', performance.yearChange, performance.yearChangePercent, theme),
          _buildMetricRow('All Time', performance.allTimeGainLoss, performance.allTimeGainLossPercent, theme),
        ],
      ),
    );
  }
  
  Widget _buildMetricRow(
    String period,
    double change,
    double changePercent,
    GlassThemeData theme,
  ) {
    final isPositive = change >= 0;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            period,
            style: theme.bodyMedium,
          ),
          Row(
            children: [
              Text(
                '${isPositive ? '+' : ''}\$${_formatCurrency(change.abs())}',
                style: TextStyle(
                  color: isPositive ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPositive ? Colors.green : Colors.red).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: isPositive ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildAllocationChart(Map<String, double> allocation, GlassThemeData theme) {
    final colors = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
    ];
    
    final sections = allocation.entries.map((entry) {
      final index = allocation.keys.toList().indexOf(entry.key);
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: entry.value,
        title: '${entry.value.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
    
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 30,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: allocation.entries.map((entry) {
              final index = allocation.keys.toList().indexOf(entry.key);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[index % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    entry.key.replaceAll('_', ' ').toUpperCase(),
                    style: theme.bodySmall,
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTransactionsTab(Portfolio portfolio, GlassThemeData theme) {
    final allTransactions = <Transaction>[];
    for (final item in portfolio.items) {
      allTransactions.addAll(item.transactions);
    }
    
    if (allTransactions.isEmpty) {
      return Center(
        child: Text(
          'No transactions yet',
          style: theme.bodyLarge.copyWith(
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      );
    }
    
    allTransactions.sort((a, b) => b.date.compareTo(a.date));
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allTransactions.length,
      itemBuilder: (context, index) {
        final transaction = allTransactions[index];
        final item = portfolio.items.firstWhere(
          (i) => i.transactions.contains(transaction),
        );
        
        return _buildTransactionCard(transaction, item, theme);
      },
    );
  }
  
  Widget _buildTransactionCard(
    Transaction transaction,
    PortfolioItem item,
    GlassThemeData theme,
  ) {
    final isBuy = transaction.type == TransactionType.buy;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        child: Row(
          children: [
            // Transaction type icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (isBuy ? Colors.green : Colors.red).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isBuy ? Icons.add : Icons.remove,
                color: isBuy ? Colors.green : Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            
            // Transaction info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${transaction.type.toString().split('.').last.toUpperCase()} ${item.symbol}',
                    style: theme.titleSmall,
                  ),
                  Text(
                    '${transaction.quantity} @ \$${transaction.price.toStringAsFixed(2)}',
                    style: theme.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            
            // Amount and date
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${_formatCurrency(transaction.totalAmount)}',
                  style: theme.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatDate(transaction.date),
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAnalyticsTab(Portfolio portfolio, GlassThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Risk metrics
        _buildRiskMetrics(portfolio, theme),
        
        const SizedBox(height: 24),
        
        // Dividend tracking
        if (portfolio.settings.trackDividends)
          _buildDividendTracking(portfolio, theme),
      ],
    );
  }
  
  Widget _buildRiskMetrics(Portfolio portfolio, GlassThemeData theme) {
    // Calculate simple risk metrics
    final volatility = _calculateVolatility(portfolio);
    final diversification = portfolio.items.length;
    
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Risk Analysis', style: theme.titleMedium),
          const SizedBox(height: 16),
          
          _buildRiskItem(
            'Volatility',
            '${volatility.toStringAsFixed(1)}%',
            volatility < 10 ? Colors.green : volatility < 20 ? Colors.orange : Colors.red,
            theme,
          ),
          
          _buildRiskItem(
            'Diversification',
            '$diversification assets',
            diversification > 10 ? Colors.green : diversification > 5 ? Colors.orange : Colors.red,
            theme,
          ),
          
          _buildRiskItem(
            'Largest Position',
            _getLargestPosition(portfolio),
            Colors.blue,
            theme,
          ),
        ],
      ),
    );
  }
  
  Widget _buildRiskItem(
    String label,
    String value,
    Color color,
    GlassThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.bodyMedium),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDividendTracking(Portfolio portfolio, GlassThemeData theme) {
    // Calculate dividend income
    final dividendTransactions = portfolio.items
        .expand((item) => item.transactions)
        .where((t) => t.type == TransactionType.dividend)
        .toList();
    
    final totalDividends = dividendTransactions.fold(
      0.0,
      (sum, t) => sum + t.totalAmount,
    );
    
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dividend Income', style: theme.titleMedium),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Dividends', style: theme.bodyMedium),
              Text(
                '\$${_formatCurrency(totalDividends)}',
                style: theme.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          
          if (dividendTransactions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Recent Dividends',
              style: theme.bodySmall.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            ...dividendTransactions.take(5).map((t) {
              final item = portfolio.items.firstWhere(
                (i) => i.transactions.contains(t),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${item.symbol} - ${_formatDate(t.date)}',
                      style: theme.bodySmall,
                    ),
                    Text(
                      '\$${t.totalAmount.toStringAsFixed(2)}',
                      style: theme.bodySmall.copyWith(
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
  
  // Helper methods
  List<FlSpot> _generateChartData(Portfolio portfolio) {
    // Generate sample data based on selected time range
    final points = _getDataPoints();
    final baseValue = portfolio.totalValue - portfolio.totalGainLoss;
    
    return List.generate(points, (index) {
      final progress = index / (points - 1);
      final value = baseValue + (portfolio.totalGainLoss * progress);
      
      // Add some random variation
      final variation = (index % 3 == 0 ? -1 : 1) * (value * 0.02);
      
      return FlSpot(index.toDouble(), value + variation);
    });
  }
  
  int _getDataPoints() {
    switch (_selectedTimeRange) {
      case '1D':
        return 24; // Hourly
      case '1W':
        return 7; // Daily
      case '1M':
        return 30; // Daily
      case '3M':
        return 90; // Daily
      case '1Y':
        return 52; // Weekly
      case 'ALL':
        return 100; // Variable
      default:
        return 30;
    }
  }
  
  String _getChartLabel(int index) {
    switch (_selectedTimeRange) {
      case '1D':
        return '${index}h';
      case '1W':
      case '1M':
      case '3M':
        return '${index}d';
      case '1Y':
        return '${index}w';
      case 'ALL':
        return '';
      default:
        return '';
    }
  }
  
  double _calculateVolatility(Portfolio portfolio) {
    // Simple volatility calculation
    return 15.5; // Placeholder
  }
  
  String _getLargestPosition(Portfolio portfolio) {
    if (portfolio.items.isEmpty) return 'N/A';
    
    final largest = portfolio.items.reduce((a, b) => 
      a.totalValue > b.totalValue ? a : b
    );
    
    final percentage = (largest.totalValue / portfolio.totalValue) * 100;
    return '${largest.symbol} (${percentage.toStringAsFixed(1)}%)';
  }
  
  void _editPortfolio() {
    // TODO: Show edit dialog
  }
  
  void _sharePortfolio() {
    // TODO: Implement share functionality
  }
  
  void _handleMenuAction(String action) {
    switch (action) {
      case 'refresh':
        // TODO: Refresh prices
        break;
      case 'export':
        // TODO: Export data
        break;
      case 'delete':
        _confirmDelete();
        break;
    }
  }
  
  void _confirmDelete() async {
    final confirmed = await showGlassConfirmDialog(
      context: context,
      title: 'Delete Portfolio',
      message: 'Are you sure you want to delete this portfolio? This action cannot be undone.',
      confirmText: 'Delete',
      destructive: true,
    );
    
    if (confirmed == true) {
      await ref.read(portfolioServiceProvider).deletePortfolio(widget.portfolio.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
  
  void _showItemActions(PortfolioItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Buy More'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show buy dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove),
              title: const Text('Sell'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show sell dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show edit dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove from Portfolio', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmRemoveItem(item);
              },
            ),
          ],
        ),
      ),
    );
  }
  
  void _confirmRemoveItem(PortfolioItem item) async {
    final confirmed = await showGlassConfirmDialog(
      context: context,
      title: 'Remove ${item.symbol}',
      message: 'Are you sure you want to remove this asset from your portfolio?',
      confirmText: 'Remove',
      destructive: true,
    );
    
    if (confirmed == true) {
      await ref.read(portfolioServiceProvider).removePortfolioItem(
        portfolioId: widget.portfolio.id,
        itemId: item.id,
      );
    }
  }
  
  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    }
    return value.toStringAsFixed(2);
  }
  
  String _formatShortCurrency(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(0)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toStringAsFixed(0);
  }
  
  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
  
  int min(int a, int b) => a < b ? a : b;
}