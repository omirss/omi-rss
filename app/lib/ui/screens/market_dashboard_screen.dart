import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../widgets/market_widgets.dart';
import '../../providers/smart_market_provider.dart';
import '../../core/services/smart_market_service.dart';

/// Simple market dashboard
class MarketDashboardScreen extends ConsumerStatefulWidget {
  const MarketDashboardScreen({super.key});
  
  @override
  ConsumerState<MarketDashboardScreen> createState() => _MarketDashboardScreenState();
}

class _MarketDashboardScreenState extends ConsumerState<MarketDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String? _searchResult;
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final watchlist = ref.watch(watchlistProvider);
    final summaryAsync = ref.watch(marketSummaryProvider);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Market',
          style: theme.headlineMedium,
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.search,
              color: Colors.white.withOpacity(0.8),
            ),
            onPressed: () => setState(() => _isSearching = !_isSearching),
          ),
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              color: Colors.white.withOpacity(0.8),
            ),
            onPressed: _showAlertsDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSearching) ...{
              _buildSearchBar(theme),
              const SizedBox(height: 16),
            },
            
            summaryAsync.when(
              data: (summary) => _buildMarketSummary(summary, theme),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            
            const SizedBox(height: 24),
            
            if (_searchResult != null) ...{
              _buildSearchResult(theme),
              const SizedBox(height: 24),
            },
            
            _buildWatchlistSection(watchlist, theme),
            
            const SizedBox(height: 24),
            
            _buildQuickAddSection(theme),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSearchBar(GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                style: theme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search ticker (e.g., AAPL)',
                  hintStyle: theme.bodyMedium.copyWith(
                    color: Colors.white.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                ),
                textCapitalization: TextCapitalization.characters,
                onSubmitted: _performSearch,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => _performSearch(_searchController.text),
            ),
          ],
        ),
      ),
    );
  }
  
  void _performSearch(String query) {
    final symbol = query.trim().toUpperCase();
    if (symbol.isNotEmpty && symbol.length <= 5) {
      setState(() {
        _searchResult = symbol;
      });
    }
  }
  
  Widget _buildSearchResult(GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Search Result',
              style: theme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => setState(() => _searchResult = null),
            ),
          ],
        ),
        const SizedBox(height: 8),
        MarketPriceCard(
          symbol: _searchResult!,
          onTap: () => _showAddToWatchlistDialog(_searchResult!),
        ),
      ],
    );
  }
  
  Widget _buildMarketSummary(MarketSummary summary, GlassThemeData theme) {
    if (summary.totalSymbols == 0) return const SizedBox.shrink();
    
    final color = summary.averageChange >= 0 ? Colors.green : Colors.red;
    
    return GlassCard(
      theme: theme,
      borderColor: color.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Watchlist Summary',
                  style: theme.titleMedium,
                ),
                Row(
                  children: [
                    Icon(
                      summary.averageChange >= 0 ? Icons.trending_up : Icons.trending_down,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${summary.averageChange >= 0 ? '+' : ''}${summary.averageChange.toStringAsFixed(2)}%',
                      style: theme.bodyMedium.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  '${summary.gainers}',
                  'Gainers',
                  Colors.green,
                  theme,
                ),
                _buildSummaryItem(
                  '${summary.losers}',
                  'Losers',
                  Colors.red,
                  theme,
                ),
                _buildSummaryItem(
                  '${summary.unchanged}',
                  'Unchanged',
                  Colors.grey,
                  theme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryItem(String value, String label, Color color, GlassThemeData theme) {
    return Column(
      children: [
        Text(
          value,
          style: theme.titleLarge.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.bodySmall.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
  
  Widget _buildWatchlistSection(List<String> watchlist, GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Watchlist',
              style: theme.titleLarge,
            ),
            TextButton(
              onPressed: _showEditWatchlistDialog,
              child: Text(
                'Edit',
                style: TextStyle(color: theme.accentColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (watchlist.isEmpty)
          Center(
            child: Column(
              children: [
                const SizedBox(height: 32),
                Icon(
                  Icons.bookmark_border,
                  size: 64,
                  color: Colors.white.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No stocks in watchlist',
                  style: theme.bodyLarge.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Search and add stocks to track',
                  style: theme.bodyMedium.copyWith(
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          )
        else
          ...watchlist.map((symbol) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MarketPriceCard(
              symbol: symbol,
              onTap: () => _showStockDetails(symbol),
            ),
          )),
      ],
    );
  }
  
  Widget _buildQuickAddSection(GlassThemeData theme) {
    const popularStocks = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA', 'META'];
    const popularCrypto = ['BTC', 'ETH', 'BNB', 'XRP', 'SOL', 'ADA'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Popular Stocks',
          style: theme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: popularStocks.map((symbol) {
            final isInWatchlist = ref.watch(watchlistProvider).contains(symbol);
            return ActionChip(
              label: Text(symbol),
              backgroundColor: isInWatchlist 
                  ? theme.accentColor.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              labelStyle: TextStyle(
                color: isInWatchlist ? theme.accentColor : Colors.white,
              ),
              onPressed: () {
                if (isInWatchlist) {
                  ref.read(watchlistProvider.notifier).removeSymbol(symbol);
                } else {
                  ref.read(watchlistProvider.notifier).addSymbol(symbol);
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Popular Crypto',
          style: theme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: popularCrypto.map((symbol) {
            final isInWatchlist = ref.watch(watchlistProvider).contains(symbol);
            return ActionChip(
              label: Text(symbol),
              backgroundColor: isInWatchlist 
                  ? theme.accentColor.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              labelStyle: TextStyle(
                color: isInWatchlist ? theme.accentColor : Colors.white,
              ),
              onPressed: () {
                if (isInWatchlist) {
                  ref.read(watchlistProvider.notifier).removeSymbol(symbol);
                } else {
                  ref.read(watchlistProvider.notifier).addSymbol(symbol);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }
  
  void _showStockDetails(String symbol) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: GlassTheme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: MarketQuotePopup(symbol: symbol),
      ),
    );
  }
  
  void _showAddToWatchlistDialog(String symbol) {
    final isInWatchlist = ref.read(watchlistProvider).contains(symbol);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.of(context).cardColor,
        title: Text(isInWatchlist ? 'Remove from Watchlist?' : 'Add to Watchlist?'),
        content: Text('$symbol will be ${isInWatchlist ? 'removed from' : 'added to'} your watchlist.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (isInWatchlist) {
                ref.read(watchlistProvider.notifier).removeSymbol(symbol);
              } else {
                ref.read(watchlistProvider.notifier).addSymbol(symbol);
              }
              Navigator.of(context).pop();
            },
            child: Text(isInWatchlist ? 'Remove' : 'Add'),
          ),
        ],
      ),
    );
  }
  
  void _showEditWatchlistDialog() {
    // TODO: Implement reorderable list dialog
  }
  
  void _showAlertsDialog() {
    // TODO: Implement price alerts dialog
  }
}