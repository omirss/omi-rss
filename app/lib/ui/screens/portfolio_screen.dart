import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/portfolio.dart';
import '../../core/services/portfolio_service.dart';
import '../../providers/portfolio_provider.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_dialog.dart';
import '../animations/loading_animation.dart';
import 'portfolio_details_screen.dart';
import 'add_portfolio_item_screen.dart';

/// Main portfolio screen
class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});
  
  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  String _selectedPortfolioId = '';
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final portfoliosAsync = ref.watch(portfoliosProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Portfolio'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreatePortfolioDialog,
            tooltip: 'Create Portfolio',
          ),
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: _showPerformanceAnalytics,
            tooltip: 'Analytics',
          ),
        ],
      ),
      body: portfoliosAsync.when(
        data: (portfolios) {
          if (portfolios.isEmpty) {
            return _buildEmptyState(theme);
          }
          
          return Column(
            children: [
              // Portfolio selector
              if (portfolios.length > 1)
                _buildPortfolioSelector(portfolios, theme),
              
              // Portfolio content
              Expanded(
                child: _selectedPortfolioId.isEmpty
                    ? _buildPortfolioOverview(portfolios, theme)
                    : _buildPortfolioDetails(
                        portfolios.firstWhere((p) => p.id == _selectedPortfolioId),
                        theme,
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: LoadingAnimation()),
        error: (error, stack) => Center(
          child: Text(
            'Error loading portfolios: $error',
            style: TextStyle(color: Colors.red.shade300),
          ),
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(GlassThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No Portfolios Yet',
            style: theme.headlineSmall.copyWith(
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Create your first portfolio to start tracking investments',
            style: theme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GlassButton(
            text: 'Create Portfolio',
            onPressed: _showCreatePortfolioDialog,
            icon: const Icon(Icons.add),
            variant: GlassButtonVariant.elevated,
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }
  
  Widget _buildPortfolioSelector(List<Portfolio> portfolios, GlassThemeData theme) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: portfolios.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            // "All" option
            final isSelected = _selectedPortfolioId.isEmpty;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GlassButton(
                text: 'All Portfolios',
                onPressed: () => setState(() => _selectedPortfolioId = ''),
                variant: isSelected 
                    ? GlassButtonVariant.elevated 
                    : GlassButtonVariant.outlined,
              ),
            );
          }
          
          final portfolio = portfolios[index - 1];
          final isSelected = portfolio.id == _selectedPortfolioId;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GlassButton(
              text: portfolio.name,
              onPressed: () => setState(() => _selectedPortfolioId = portfolio.id),
              variant: isSelected 
                  ? GlassButtonVariant.elevated 
                  : GlassButtonVariant.outlined,
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildPortfolioOverview(List<Portfolio> portfolios, GlassThemeData theme) {
    // Calculate totals across all portfolios
    double totalValue = 0;
    double totalGainLoss = 0;
    double dayChange = 0;
    
    for (final portfolio in portfolios) {
      totalValue += portfolio.totalValue;
      totalGainLoss += portfolio.totalGainLoss;
      dayChange += portfolio.dayChange;
    }
    
    final totalGainLossPercent = totalValue > 0 
        ? (totalGainLoss / (totalValue - totalGainLoss)) * 100 
        : 0.0;
    final dayChangePercent = (totalValue - dayChange) > 0
        ? (dayChange / (totalValue - dayChange)) * 100
        : 0.0;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Total value card
        _buildTotalValueCard(
          totalValue: totalValue,
          totalGainLoss: totalGainLoss,
          totalGainLossPercent: totalGainLossPercent,
          dayChange: dayChange,
          dayChangePercent: dayChangePercent,
          theme: theme,
        ).animate().fadeIn().slideY(),
        
        const SizedBox(height: 24),
        
        // Individual portfolios
        Text(
          'Portfolios',
          style: theme.titleLarge,
        ),
        const SizedBox(height: 16),
        
        ...portfolios.map((portfolio) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildPortfolioCard(portfolio, theme)
              .animate(delay: (portfolios.indexOf(portfolio) * 100).ms)
              .fadeIn()
              .slideX(),
        )),
        
        // Asset allocation
        if (totalValue > 0) ...[
          const SizedBox(height: 24),
          Text(
            'Asset Allocation',
            style: theme.titleLarge,
          ),
          const SizedBox(height: 16),
          _buildAssetAllocationChart(portfolios, theme)
              .animate(delay: 300.ms).fadeIn().scale(),
        ],
      ],
    );
  }
  
  Widget _buildPortfolioDetails(Portfolio portfolio, GlassThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Portfolio value card
        _buildTotalValueCard(
          totalValue: portfolio.totalValue,
          totalGainLoss: portfolio.totalGainLoss,
          totalGainLossPercent: portfolio.totalGainLossPercent,
          dayChange: portfolio.dayChange,
          dayChangePercent: portfolio.dayChangePercent,
          theme: theme,
        ).animate().fadeIn().slideY(),
        
        const SizedBox(height: 24),
        
        // Portfolio items
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Holdings',
              style: theme.titleLarge,
            ),
            GlassButton(
              text: 'Add',
              onPressed: () => _navigateToAddItem(portfolio),
              icon: const Icon(Icons.add, size: 16),
              variant: GlassButtonVariant.text,
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        if (portfolio.items.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No holdings yet',
                style: theme.bodyLarge.copyWith(
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          )
        else
          ...portfolio.items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildPortfolioItemCard(item, theme)
                .animate(delay: (portfolio.items.indexOf(item) * 100).ms)
                .fadeIn()
                .slideX(),
          )),
      ],
    );
  }
  
  Widget _buildTotalValueCard({
    required double totalValue,
    required double totalGainLoss,
    required double totalGainLossPercent,
    required double dayChange,
    required double dayChangePercent,
    required GlassThemeData theme,
  }) {
    final isPositive = totalGainLoss >= 0;
    final isDayPositive = dayChange >= 0;
    
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Value',
            style: theme.bodyLarge.copyWith(
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\$${_formatCurrency(totalValue)}',
            style: theme.headlineLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Total gain/loss
          Row(
            children: [
              Icon(
                isPositive ? Icons.trending_up : Icons.trending_down,
                color: isPositive ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${isPositive ? '+' : ''}\$${_formatCurrency(totalGainLoss.abs())}',
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
                  '${isPositive ? '+' : ''}${totalGainLossPercent.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: isPositive ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Day change
          Row(
            children: [
              Text(
                'Today: ',
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              Text(
                '${isDayPositive ? '+' : ''}\$${_formatCurrency(dayChange.abs())}',
                style: TextStyle(
                  color: isDayPositive ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${isDayPositive ? '+' : ''}${dayChangePercent.toStringAsFixed(2)}%)',
                style: TextStyle(
                  color: isDayPositive ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPortfolioCard(Portfolio portfolio, GlassThemeData theme) {
    final isPositive = portfolio.totalGainLoss >= 0;
    
    return GlassCard(
      onTap: () => _navigateToPortfolioDetails(portfolio),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      portfolio.name,
                      style: theme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${portfolio.items.length} holdings',
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${_formatCurrency(portfolio.totalValue)}',
                    style: theme.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                        color: isPositive ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${portfolio.totalGainLossPercent.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: isPositive ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Mini chart
          SizedBox(
            height: 50,
            child: _buildMiniChart(portfolio, theme),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPortfolioItemCard(PortfolioItem item, GlassThemeData theme) {
    final isPositive = item.gainLoss >= 0;
    final isDayPositive = item.dayChange >= 0;
    
    return GlassCard(
      onTap: () => _showItemDetails(item),
      child: Row(
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
          
          // Item info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.symbol,
                  style: theme.titleSmall,
                ),
                Text(
                  '${item.quantity} @ \$${item.averageCost.toStringAsFixed(2)}',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          
          // Current value
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${item.currentPrice.toStringAsFixed(2)}',
                style: theme.titleSmall.copyWith(
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
          
          const SizedBox(width: 16),
          
          // Total value & gain/loss
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${_formatCurrency(item.totalValue)}',
                style: theme.titleSmall,
              ),
              Text(
                '${isPositive ? '+' : ''}\$${_formatCurrency(item.gainLoss.abs())}',
                style: TextStyle(
                  color: isPositive ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMiniChart(Portfolio portfolio, GlassThemeData theme) {
    // Simulate historical data
    final spots = List.generate(7, (index) {
      final value = portfolio.totalValue * (1 + (index - 3) * 0.02);
      return FlSpot(index.toDouble(), value);
    });
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: portfolio.totalGainLoss >= 0 ? Colors.green : Colors.red,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: (portfolio.totalGainLoss >= 0 ? Colors.green : Colors.red)
                  .withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAssetAllocationChart(List<Portfolio> portfolios, GlassThemeData theme) {
    // Calculate asset allocation across all portfolios
    final assetAllocation = <String, double>{};
    double totalValue = 0;
    
    for (final portfolio in portfolios) {
      for (final item in portfolio.items) {
        final assetType = item.type.toString().split('.').last;
        assetAllocation[assetType] = 
            (assetAllocation[assetType] ?? 0) + item.totalValue;
        totalValue += item.totalValue;
      }
    }
    
    final sections = assetAllocation.entries.map((entry) {
      final percentage = (entry.value / totalValue) * 100;
      return PieChartSectionData(
        color: _getAssetTypeColor(entry.key),
        value: entry.value,
        title: '${percentage.toStringAsFixed(1)}%',
        radius: 80,
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
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: assetAllocation.entries.map((entry) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _getAssetTypeColor(entry.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    entry.key.toUpperCase(),
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
  
  void _showCreatePortfolioDialog() {
    final nameController = TextEditingController();
    PortfolioType selectedType = PortfolioType.mixed;
    
    showGlassDialog(
      context: context,
      title: const Text('Create Portfolio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Portfolio Name',
              hintText: 'e.g., Long-term Investments',
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<PortfolioType>(
            value: selectedType,
            decoration: const InputDecoration(
              labelText: 'Portfolio Type',
            ),
            dropdownColor: Colors.grey.shade900,
            style: const TextStyle(color: Colors.white),
            items: PortfolioType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type.toString().split('.').last.toUpperCase()),
              );
            }).toList(),
            onChanged: (type) {
              if (type != null) {
                selectedType = type;
              }
            },
          ),
        ],
      ),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Create',
          onPressed: () async {
            if (nameController.text.isNotEmpty) {
              Navigator.of(context).pop();
              await ref.read(portfolioServiceProvider).createPortfolio(
                name: nameController.text,
                type: selectedType,
              );
            }
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
  
  void _navigateToPortfolioDetails(Portfolio portfolio) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PortfolioDetailsScreen(portfolio: portfolio),
      ),
    );
  }
  
  void _navigateToAddItem(Portfolio portfolio) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddPortfolioItemScreen(portfolio: portfolio),
      ),
    );
  }
  
  void _showItemDetails(PortfolioItem item) {
    // TODO: Show item details dialog
  }
  
  void _showPerformanceAnalytics() {
    // TODO: Navigate to analytics screen
  }
  
  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    }
    return value.toStringAsFixed(2);
  }
  
  Color _getAssetTypeColor(String assetType) {
    switch (assetType) {
      case 'stock':
        return Colors.blue;
      case 'crypto':
        return Colors.orange;
      case 'etf':
        return Colors.green;
      case 'bond':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
  
  int min(int a, int b) => a < b ? a : b;
}