import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/market_service.dart';
import '../core/services/polygon_provider.dart';
import '../core/services/coinmarketcap_provider.dart';
import '../core/database/database.dart';
import 'database_provider.dart';

/// Market service provider
final marketServiceProvider = Provider<MarketService>((ref) {
  final database = ref.watch(databaseProvider);
  return MarketService(database: database);
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
    // TODO: Load from database/preferences
    state = ['AAPL', 'GOOGL', 'MSFT', 'BTC', 'ETH'];
  }
  
  Future<void> addSymbol(String symbol) async {
    if (!state.contains(symbol)) {
      state = [...state, symbol];
      // TODO: Save to database/preferences
    }
  }
  
  Future<void> removeSymbol(String symbol) async {
    state = state.where((s) => s != symbol).toList();
    // TODO: Save to database/preferences
  }
  
  bool contains(String symbol) => state.contains(symbol);
}

/// Stock quotes provider
final stockQuotesProvider = FutureProvider.family<List<StockQuote>, List<String>>((ref, symbols) async {
  final service = ref.watch(marketServiceProvider);
  return await service.getStockQuotes(symbols);
});

/// Single stock quote provider
final stockQuoteProvider = FutureProvider.family<StockQuote?, String>((ref, symbol) async {
  final service = ref.watch(marketServiceProvider);
  return await service.getStockQuote(symbol);
});

/// Crypto quotes provider
final cryptoQuotesProvider = FutureProvider.family<List<CryptoQuote>, List<String>>((ref, symbols) async {
  final service = ref.watch(marketServiceProvider);
  return await service.getCryptoQuotes(symbols);
});

/// Single crypto quote provider
final cryptoQuoteProvider = FutureProvider.family<CryptoQuote?, String>((ref, symbol) async {
  final service = ref.watch(marketServiceProvider);
  return await service.getCryptoQuote(symbol);
});

/// Forex quote provider
final forexQuoteProvider = FutureProvider.family<ForexQuote?, String>((ref, pair) async {
  final service = ref.watch(marketServiceProvider);
  return await service.getForexQuote(pair);
});

/// Market news provider
final marketNewsProvider = FutureProvider.family<List<MarketNews>, List<String>?>((ref, symbols) async {
  final service = ref.watch(marketServiceProvider);
  return await service.getMarketNews(symbols: symbols);
});

/// Stock stream provider
final stockStreamProvider = StreamProvider.family<StockQuote, String>((ref, symbol) {
  final service = ref.watch(marketServiceProvider);
  final stream = service.streamStockQuote(symbol);
  if (stream == null) {
    // If no stream available, poll every 5 seconds
    return Stream.periodic(const Duration(seconds: 5), (_) async {
      return await service.getStockQuote(symbol);
    }).asyncMap((future) => future).where((quote) => quote != null).cast<StockQuote>();
  }
  return stream;
});

/// Crypto stream provider
final cryptoStreamProvider = StreamProvider.family<CryptoQuote, String>((ref, symbol) {
  final service = ref.watch(marketServiceProvider);
  final stream = service.streamCryptoQuote(symbol);
  if (stream == null) {
    // If no stream available, poll every 5 seconds
    return Stream.periodic(const Duration(seconds: 5), (_) async {
      return await service.getCryptoQuote(symbol);
    }).asyncMap((future) => future).where((quote) => quote != null).cast<CryptoQuote>();
  }
  return stream;
});

/// Portfolio provider
final portfolioProvider = StateNotifierProvider<PortfolioNotifier, Portfolio>((ref) {
  return PortfolioNotifier(ref);
});

/// Portfolio model
class Portfolio {
  final List<PortfolioItem> items;
  final double totalValue;
  final double totalCost;
  final double totalGainLoss;
  final double totalGainLossPercent;
  
  Portfolio({
    this.items = const [],
    this.totalValue = 0,
    this.totalCost = 0,
    this.totalGainLoss = 0,
    this.totalGainLossPercent = 0,
  });
  
  Portfolio copyWith({
    List<PortfolioItem>? items,
    double? totalValue,
    double? totalCost,
    double? totalGainLoss,
    double? totalGainLossPercent,
  }) {
    return Portfolio(
      items: items ?? this.items,
      totalValue: totalValue ?? this.totalValue,
      totalCost: totalCost ?? this.totalCost,
      totalGainLoss: totalGainLoss ?? this.totalGainLoss,
      totalGainLossPercent: totalGainLossPercent ?? this.totalGainLossPercent,
    );
  }
}

/// Portfolio item model
class PortfolioItem {
  final String symbol;
  final String name;
  final String type; // stock, crypto, forex
  final double shares;
  final double averageCost;
  final double currentPrice;
  final double value;
  final double gainLoss;
  final double gainLossPercent;
  final DateTime? lastUpdated;
  
  PortfolioItem({
    required this.symbol,
    required this.name,
    required this.type,
    required this.shares,
    required this.averageCost,
    required this.currentPrice,
    required this.value,
    required this.gainLoss,
    required this.gainLossPercent,
    this.lastUpdated,
  });
}

/// Portfolio notifier
class PortfolioNotifier extends StateNotifier<Portfolio> {
  final Ref ref;
  
  PortfolioNotifier(this.ref) : super(Portfolio()) {
    _loadPortfolio();
  }
  
  Future<void> _loadPortfolio() async {
    // TODO: Load from database
    // For now, use dummy data
    state = Portfolio(
      items: [
        PortfolioItem(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          type: 'stock',
          shares: 100,
          averageCost: 150.00,
          currentPrice: 175.00,
          value: 17500.00,
          gainLoss: 2500.00,
          gainLossPercent: 16.67,
          lastUpdated: DateTime.now(),
        ),
        PortfolioItem(
          symbol: 'BTC',
          name: 'Bitcoin',
          type: 'crypto',
          shares: 0.5,
          averageCost: 30000.00,
          currentPrice: 45000.00,
          value: 22500.00,
          gainLoss: 7500.00,
          gainLossPercent: 50.00,
          lastUpdated: DateTime.now(),
        ),
      ],
      totalValue: 40000.00,
      totalCost: 30000.00,
      totalGainLoss: 10000.00,
      totalGainLossPercent: 33.33,
    );
  }
  
  Future<void> addPosition(
    String symbol,
    String name,
    String type,
    double shares,
    double price,
  ) async {
    final existingIndex = state.items.indexWhere((item) => item.symbol == symbol);
    
    if (existingIndex >= 0) {
      // Update existing position
      final existing = state.items[existingIndex];
      final totalShares = existing.shares + shares;
      final totalCost = (existing.shares * existing.averageCost) + (shares * price);
      final averageCost = totalCost / totalShares;
      
      final updatedItem = PortfolioItem(
        symbol: symbol,
        name: name,
        type: type,
        shares: totalShares,
        averageCost: averageCost,
        currentPrice: existing.currentPrice,
        value: totalShares * existing.currentPrice,
        gainLoss: (totalShares * existing.currentPrice) - totalCost,
        gainLossPercent: ((existing.currentPrice - averageCost) / averageCost) * 100,
        lastUpdated: DateTime.now(),
      );
      
      final items = [...state.items];
      items[existingIndex] = updatedItem;
      
      _updatePortfolio(items);
    } else {
      // Add new position
      final newItem = PortfolioItem(
        symbol: symbol,
        name: name,
        type: type,
        shares: shares,
        averageCost: price,
        currentPrice: price,
        value: shares * price,
        gainLoss: 0,
        gainLossPercent: 0,
        lastUpdated: DateTime.now(),
      );
      
      _updatePortfolio([...state.items, newItem]);
    }
    
    // TODO: Save to database
  }
  
  Future<void> removePosition(String symbol) async {
    final items = state.items.where((item) => item.symbol != symbol).toList();
    _updatePortfolio(items);
    // TODO: Save to database
  }
  
  Future<void> updatePrices() async {
    final service = ref.read(marketServiceProvider);
    final updatedItems = <PortfolioItem>[];
    
    for (final item in state.items) {
      double currentPrice = item.currentPrice;
      
      if (item.type == 'stock') {
        final quote = await service.getStockQuote(item.symbol);
        if (quote != null) {
          currentPrice = quote.price;
        }
      } else if (item.type == 'crypto') {
        final quote = await service.getCryptoQuote(item.symbol);
        if (quote != null) {
          currentPrice = quote.price;
        }
      }
      
      final value = item.shares * currentPrice;
      final totalCost = item.shares * item.averageCost;
      final gainLoss = value - totalCost;
      final gainLossPercent = (gainLoss / totalCost) * 100;
      
      updatedItems.add(PortfolioItem(
        symbol: item.symbol,
        name: item.name,
        type: item.type,
        shares: item.shares,
        averageCost: item.averageCost,
        currentPrice: currentPrice,
        value: value,
        gainLoss: gainLoss,
        gainLossPercent: gainLossPercent,
        lastUpdated: DateTime.now(),
      ));
    }
    
    _updatePortfolio(updatedItems);
  }
  
  void _updatePortfolio(List<PortfolioItem> items) {
    double totalValue = 0;
    double totalCost = 0;
    
    for (final item in items) {
      totalValue += item.value;
      totalCost += item.shares * item.averageCost;
    }
    
    final totalGainLoss = totalValue - totalCost;
    final totalGainLossPercent = totalCost > 0 ? (totalGainLoss / totalCost) * 100 : 0;
    
    state = Portfolio(
      items: items,
      totalValue: totalValue,
      totalCost: totalCost,
      totalGainLoss: totalGainLoss,
      totalGainLossPercent: totalGainLossPercent,
    );
  }
}

/// Market settings provider
final marketSettingsProvider = StateNotifierProvider<MarketSettingsNotifier, MarketSettings>((ref) {
  return MarketSettingsNotifier();
});

/// Market settings model
class MarketSettings {
  final bool enableStreaming;
  final int refreshInterval; // seconds
  final String defaultProvider;
  final bool showExtendedHours;
  final String currency;
  final List<String> enabledProviders;
  
  MarketSettings({
    this.enableStreaming = true,
    this.refreshInterval = 5,
    this.defaultProvider = 'Yahoo Finance',
    this.showExtendedHours = false,
    this.currency = 'USD',
    this.enabledProviders = const ['Yahoo Finance', 'Alpha Vantage', 'Finnhub'],
  });
  
  MarketSettings copyWith({
    bool? enableStreaming,
    int? refreshInterval,
    String? defaultProvider,
    bool? showExtendedHours,
    String? currency,
    List<String>? enabledProviders,
  }) {
    return MarketSettings(
      enableStreaming: enableStreaming ?? this.enableStreaming,
      refreshInterval: refreshInterval ?? this.refreshInterval,
      defaultProvider: defaultProvider ?? this.defaultProvider,
      showExtendedHours: showExtendedHours ?? this.showExtendedHours,
      currency: currency ?? this.currency,
      enabledProviders: enabledProviders ?? this.enabledProviders,
    );
  }
}

/// Market settings notifier
class MarketSettingsNotifier extends StateNotifier<MarketSettings> {
  MarketSettingsNotifier() : super(MarketSettings()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    // TODO: Load from preferences
  }
  
  Future<void> _saveSettings() async {
    // TODO: Save to preferences
  }
  
  void setEnableStreaming(bool value) {
    state = state.copyWith(enableStreaming: value);
    _saveSettings();
  }
  
  void setRefreshInterval(int seconds) {
    state = state.copyWith(refreshInterval: seconds);
    _saveSettings();
  }
  
  void setDefaultProvider(String provider) {
    state = state.copyWith(defaultProvider: provider);
    _saveSettings();
  }
  
  void setShowExtendedHours(bool value) {
    state = state.copyWith(showExtendedHours: value);
    _saveSettings();
  }
  
  void setCurrency(String currency) {
    state = state.copyWith(currency: currency);
    _saveSettings();
  }
  
  void setEnabledProviders(List<String> providers) {
    state = state.copyWith(enabledProviders: providers);
    _saveSettings();
  }
}