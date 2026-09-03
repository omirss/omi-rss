import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/smart_market_service.dart';
import '../core/database/database.dart';
import 'database_provider.dart';

/// Smart market service provider
final smartMarketServiceProvider = Provider<SmartMarketService>((ref) {
  final database = ref.watch(databaseProvider);
  return SmartMarketService(database: database);
});

/// Market quote provider with caching
final marketQuoteProvider = FutureProvider.family<MarketQuote?, String>((ref, symbol) async {
  final service = ref.watch(smartMarketServiceProvider);
  
  // Refresh every 5 minutes
  ref.keepAlive();
  final timer = Future.delayed(const Duration(minutes: 5), () {
    ref.invalidateSelf();
  });
  ref.onDispose(() => timer);
  
  return await service.getQuote(symbol);
});

/// Batch quotes provider
final marketQuotesProvider = FutureProvider.family<Map<String, MarketQuote>, List<String>>((ref, symbols) async {
  final service = ref.watch(smartMarketServiceProvider);
  
  // Refresh every 5 minutes
  ref.keepAlive();
  final timer = Future.delayed(const Duration(minutes: 5), () {
    ref.invalidateSelf();
  });
  ref.onDispose(() => timer);
  
  return await service.getQuotes(symbols);
});

/// Article mentions provider
final articleMentionsProvider = FutureProvider.family<Map<String, MarketQuote>, String>((ref, content) async {
  final service = ref.watch(smartMarketServiceProvider);
  return await service.getArticleMentions(content);
});

/// Watchlist provider
final watchlistProvider = StateNotifierProvider<WatchlistNotifier, List<String>>((ref) {
  return WatchlistNotifier(ref);
});

class WatchlistNotifier extends StateNotifier<List<String>> {
  final Ref ref;
  
  WatchlistNotifier(this.ref) : super([]) {
    _loadWatchlist();
  }
  
  Future<void> _loadWatchlist() async {
    // TODO: Load from shared preferences
    state = ['AAPL', 'GOOGL', 'MSFT', 'BTC', 'ETH'];
  }
  
  Future<void> _saveWatchlist() async {
    // TODO: Save to shared preferences
    // Preload quotes for new watchlist
    final service = ref.read(smartMarketServiceProvider);
    await service.preloadWatchlist(state);
  }
  
  void addSymbol(String symbol) {
    if (!state.contains(symbol)) {
      state = [...state, symbol];
      _saveWatchlist();
    }
  }
  
  void removeSymbol(String symbol) {
    state = state.where((s) => s != symbol).toList();
    _saveWatchlist();
  }
  
  bool contains(String symbol) => state.contains(symbol);
  
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final items = [...state];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    state = items;
    _saveWatchlist();
  }
}

/// Price alert provider
final priceAlertsProvider = StateNotifierProvider<PriceAlertNotifier, List<PriceAlert>>((ref) {
  return PriceAlertNotifier(ref);
});

/// Price alert model
class PriceAlert {
  final String id;
  final String symbol;
  final double targetPrice;
  final AlertType type;
  final bool isActive;
  final DateTime createdAt;
  final String? relatedArticleId;
  
  PriceAlert({
    required this.id,
    required this.symbol,
    required this.targetPrice,
    required this.type,
    this.isActive = true,
    required this.createdAt,
    this.relatedArticleId,
  });
}

enum AlertType {
  above,
  below,
  percentChange,
}

class PriceAlertNotifier extends StateNotifier<List<PriceAlert>> {
  final Ref ref;
  
  PriceAlertNotifier(this.ref) : super([]) {
    _loadAlerts();
  }
  
  Future<void> _loadAlerts() async {
    // TODO: Load from database
  }
  
  Future<void> _saveAlerts() async {
    // TODO: Save to database
  }
  
  void addAlert(PriceAlert alert) {
    state = [...state, alert];
    _saveAlerts();
  }
  
  void removeAlert(String id) {
    state = state.where((a) => a.id != id).toList();
    _saveAlerts();
  }
  
  void toggleAlert(String id) {
    state = state.map((alert) {
      if (alert.id == id) {
        return PriceAlert(
          id: alert.id,
          symbol: alert.symbol,
          targetPrice: alert.targetPrice,
          type: alert.type,
          isActive: !alert.isActive,
          createdAt: alert.createdAt,
          relatedArticleId: alert.relatedArticleId,
        );
      }
      return alert;
    }).toList();
    _saveAlerts();
  }
  
  Future<void> checkAlerts() async {
    final service = ref.read(smartMarketServiceProvider);
    final activeAlerts = state.where((a) => a.isActive).toList();
    
    if (activeAlerts.isEmpty) return;
    
    // Get unique symbols
    final symbols = activeAlerts.map((a) => a.symbol).toSet().toList();
    final quotes = await service.getQuotes(symbols);
    
    for (final alert in activeAlerts) {
      final quote = quotes[alert.symbol];
      if (quote == null) continue;
      
      bool triggered = false;
      
      switch (alert.type) {
        case AlertType.above:
          triggered = quote.price >= alert.targetPrice;
          break;
        case AlertType.below:
          triggered = quote.price <= alert.targetPrice;
          break;
        case AlertType.percentChange:
          triggered = quote.changePercent.abs() >= alert.targetPrice;
          break;
      }
      
      if (triggered) {
        // TODO: Show notification
        // Disable alert after triggering
        toggleAlert(alert.id);
      }
    }
  }
}

/// Market summary provider
final marketSummaryProvider = FutureProvider<MarketSummary>((ref) async {
  final watchlist = ref.watch(watchlistProvider);
  final service = ref.watch(smartMarketServiceProvider);
  
  if (watchlist.isEmpty) {
    return MarketSummary.empty();
  }
  
  final quotes = await service.getQuotes(watchlist);
  
  int gainers = 0;
  int losers = 0;
  double totalChange = 0;
  
  for (final quote in quotes.values) {
    if (quote.change > 0) {
      gainers++;
    } else if (quote.change < 0) {
      losers++;
    }
    totalChange += quote.changePercent;
  }
  
  return MarketSummary(
    totalSymbols: quotes.length,
    gainers: gainers,
    losers: losers,
    unchanged: quotes.length - gainers - losers,
    averageChange: quotes.isNotEmpty ? totalChange / quotes.length : 0,
  );
});

/// Market summary model
class MarketSummary {
  final int totalSymbols;
  final int gainers;
  final int losers;
  final int unchanged;
  final double averageChange;
  
  MarketSummary({
    required this.totalSymbols,
    required this.gainers,
    required this.losers,
    required this.unchanged,
    required this.averageChange,
  });
  
  factory MarketSummary.empty() => MarketSummary(
    totalSymbols: 0,
    gainers: 0,
    losers: 0,
    unchanged: 0,
    averageChange: 0,
  );
}