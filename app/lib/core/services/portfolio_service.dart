import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import '../models/portfolio.dart';
import '../database/database.dart';
import '../../providers/settings_provider.dart';

/// Service for managing investment portfolios
class PortfolioService {
  final AppDatabase _database;
  final Dio _dio;
  final SettingsService _settingsService;
  
  // Cache for portfolio data
  final Map<String, Portfolio> _portfolioCache = {};
  final Map<String, MarketData> _marketDataCache = {};
  final Map<String, DateTime> _lastUpdateTime = {};
  
  // Real-time data streams
  final _portfolioStreamController = StreamController<Portfolio>.broadcast();
  final _marketDataStreamController = StreamController<MarketData>.broadcast();
  final _alertStreamController = StreamController<PortfolioAlert>.broadcast();
  
  // API endpoints
  static const _stockApiUrl = 'https://api.polygon.io/v2';
  static const _cryptoApiUrl = 'https://api.coingecko.com/api/v3';
  static const _finnhubApiUrl = 'https://finnhub.io/api/v1';
  
  Timer? _refreshTimer;
  
  PortfolioService({
    required AppDatabase database,
    required SettingsService settingsService,
    Dio? dio,
  }) : _database = database,
       _settingsService = settingsService,
       _dio = dio ?? Dio() {
    _initialize();
  }
  
  void _initialize() {
    // Start periodic refresh
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshMarketData(),
    );
  }
  
  void dispose() {
    _refreshTimer?.cancel();
    _portfolioStreamController.close();
    _marketDataStreamController.close();
    _alertStreamController.close();
  }
  
  // Streams
  Stream<Portfolio> get portfolioStream => _portfolioStreamController.stream;
  Stream<MarketData> get marketDataStream => _marketDataStreamController.stream;
  Stream<PortfolioAlert> get alertStream => _alertStreamController.stream;
  
  /// Create a new portfolio
  Future<Portfolio> createPortfolio({
    required String name,
    required PortfolioType type,
    PortfolioSettings? settings,
  }) async {
    final portfolio = Portfolio(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      userId: 'default', // TODO: Get from auth
      type: type,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      items: [],
      settings: settings ?? const PortfolioSettings(),
    );
    
    // Save to database
    await _savePortfolio(portfolio);
    
    // Update cache
    _portfolioCache[portfolio.id] = portfolio;
    _portfolioStreamController.add(portfolio);
    
    return portfolio;
  }
  
  /// Get all portfolios
  Future<List<Portfolio>> getPortfolios() async {
    // TODO: Load from database
    return _portfolioCache.values.toList();
  }
  
  /// Get portfolio by ID
  Future<Portfolio?> getPortfolio(String id) async {
    if (_portfolioCache.containsKey(id)) {
      return _portfolioCache[id];
    }
    
    // TODO: Load from database
    return null;
  }
  
  /// Add item to portfolio
  Future<Portfolio> addPortfolioItem({
    required String portfolioId,
    required String symbol,
    required String name,
    required AssetType type,
    required double quantity,
    required double price,
    DateTime? purchaseDate,
  }) async {
    final portfolio = await getPortfolio(portfolioId);
    if (portfolio == null) {
      throw Exception('Portfolio not found');
    }
    
    // Check if item already exists
    final existingItem = portfolio.items.firstWhereOrNull(
      (item) => item.symbol == symbol,
    );
    
    if (existingItem != null) {
      // Update existing item
      return await _updatePortfolioItem(
        portfolio: portfolio,
        itemId: existingItem.id,
        quantity: existingItem.quantity + quantity,
        averageCost: ((existingItem.totalCost + (quantity * price)) / 
                     (existingItem.quantity + quantity)),
      );
    }
    
    // Create new item
    final item = PortfolioItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      portfolioId: portfolioId,
      symbol: symbol,
      name: name,
      type: type,
      quantity: quantity,
      averageCost: price,
      currentPrice: price,
      purchaseDate: purchaseDate ?? DateTime.now(),
      totalCost: quantity * price,
      transactions: [
        Transaction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          portfolioItemId: '',
          type: TransactionType.buy,
          quantity: quantity,
          price: price,
          totalAmount: quantity * price,
          date: purchaseDate ?? DateTime.now(),
        ),
      ],
    );
    
    // Update portfolio
    final updatedItems = [...portfolio.items, item];
    final updatedPortfolio = portfolio.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now(),
    );
    
    await _savePortfolio(updatedPortfolio);
    _portfolioCache[portfolioId] = updatedPortfolio;
    _portfolioStreamController.add(updatedPortfolio);
    
    // Fetch latest market data
    await _fetchMarketData(symbol, type);
    
    return updatedPortfolio;
  }
  
  /// Update portfolio item
  Future<Portfolio> _updatePortfolioItem({
    required Portfolio portfolio,
    required String itemId,
    double? quantity,
    double? averageCost,
  }) async {
    final updatedItems = portfolio.items.map((item) {
      if (item.id == itemId) {
        return item.copyWith(
          quantity: quantity ?? item.quantity,
          averageCost: averageCost ?? item.averageCost,
          totalCost: (quantity ?? item.quantity) * (averageCost ?? item.averageCost),
        );
      }
      return item;
    }).toList();
    
    final updatedPortfolio = portfolio.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now(),
    );
    
    await _savePortfolio(updatedPortfolio);
    _portfolioCache[portfolio.id] = updatedPortfolio;
    _portfolioStreamController.add(updatedPortfolio);
    
    return updatedPortfolio;
  }
  
  /// Remove item from portfolio
  Future<Portfolio> removePortfolioItem({
    required String portfolioId,
    required String itemId,
  }) async {
    final portfolio = await getPortfolio(portfolioId);
    if (portfolio == null) {
      throw Exception('Portfolio not found');
    }
    
    final updatedItems = portfolio.items
        .where((item) => item.id != itemId)
        .toList();
    
    final updatedPortfolio = portfolio.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now(),
    );
    
    await _savePortfolio(updatedPortfolio);
    _portfolioCache[portfolioId] = updatedPortfolio;
    _portfolioStreamController.add(updatedPortfolio);
    
    return updatedPortfolio;
  }
  
  /// Record a transaction
  Future<Portfolio> recordTransaction({
    required String portfolioId,
    required String itemId,
    required TransactionType type,
    required double quantity,
    required double price,
    DateTime? date,
    String? notes,
  }) async {
    final portfolio = await getPortfolio(portfolioId);
    if (portfolio == null) {
      throw Exception('Portfolio not found');
    }
    
    final item = portfolio.items.firstWhereOrNull((i) => i.id == itemId);
    if (item == null) {
      throw Exception('Portfolio item not found');
    }
    
    final transaction = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      portfolioItemId: itemId,
      type: type,
      quantity: quantity,
      price: price,
      totalAmount: quantity * price,
      date: date ?? DateTime.now(),
      notes: notes,
    );
    
    // Update item based on transaction type
    double newQuantity = item.quantity;
    double newAverageCost = item.averageCost;
    
    switch (type) {
      case TransactionType.buy:
        newQuantity += quantity;
        newAverageCost = ((item.totalCost + (quantity * price)) / newQuantity);
        break;
      case TransactionType.sell:
        newQuantity -= quantity;
        if (newQuantity < 0) newQuantity = 0;
        break;
      case TransactionType.dividend:
        // Dividends don't affect quantity or cost
        break;
      case TransactionType.split:
        newQuantity *= quantity; // quantity represents split ratio
        newAverageCost /= quantity;
        break;
      default:
        break;
    }
    
    final updatedItem = item.copyWith(
      quantity: newQuantity,
      averageCost: newAverageCost,
      totalCost: newQuantity * newAverageCost,
      transactions: [...item.transactions, transaction],
    );
    
    final updatedItems = portfolio.items.map((i) {
      return i.id == itemId ? updatedItem : i;
    }).toList();
    
    final updatedPortfolio = portfolio.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now(),
    );
    
    await _savePortfolio(updatedPortfolio);
    _portfolioCache[portfolioId] = updatedPortfolio;
    _portfolioStreamController.add(updatedPortfolio);
    
    return updatedPortfolio;
  }
  
  /// Fetch market data for a symbol
  Future<MarketData?> _fetchMarketData(String symbol, AssetType type) async {
    try {
      switch (type) {
        case AssetType.stock:
        case AssetType.etf:
          return await _fetchStockData(symbol);
        case AssetType.crypto:
          return await _fetchCryptoData(symbol);
        default:
          return null;
      }
    } catch (e) {
      print('Error fetching market data for $symbol: $e');
      return null;
    }
  }
  
  /// Fetch stock data from API
  Future<MarketData?> _fetchStockData(String symbol) async {
    try {
      // Try Polygon.io first
      final polygonKey = _settingsService.getSetting('polygon_api_key');
      if (polygonKey != null) {
        final response = await _dio.get(
          '$_stockApiUrl/aggs/ticker/$symbol/prev',
          queryParameters: {'apiKey': polygonKey},
        );
        
        if (response.statusCode == 200) {
          final data = response.data['results'][0];
          final marketData = MarketData(
            symbol: symbol,
            price: data['c'].toDouble(),
            previousClose: data['c'].toDouble(),
            dayHigh: data['h'].toDouble(),
            dayLow: data['l'].toDouble(),
            volume: data['v'].toDouble(),
            marketCap: 0, // Not available in this endpoint
            peRatio: 0,
            dividendYield: 0,
            week52High: 0,
            week52Low: 0,
            timestamp: DateTime.now(),
          );
          
          _marketDataCache[symbol] = marketData;
          _marketDataStreamController.add(marketData);
          return marketData;
        }
      }
      
      // Fallback to Finnhub
      final finnhubKey = _settingsService.getSetting('finnhub_api_key');
      if (finnhubKey != null) {
        final response = await _dio.get(
          '$_finnhubApiUrl/quote',
          queryParameters: {
            'symbol': symbol,
            'token': finnhubKey,
          },
        );
        
        if (response.statusCode == 200) {
          final data = response.data;
          final marketData = MarketData(
            symbol: symbol,
            price: data['c'].toDouble(),
            previousClose: data['pc'].toDouble(),
            dayHigh: data['h'].toDouble(),
            dayLow: data['l'].toDouble(),
            volume: 0, // Not in basic quote
            marketCap: 0,
            peRatio: 0,
            dividendYield: 0,
            week52High: 0,
            week52Low: 0,
            timestamp: DateTime.now(),
          );
          
          _marketDataCache[symbol] = marketData;
          _marketDataStreamController.add(marketData);
          return marketData;
        }
      }
      
      return null;
    } catch (e) {
      print('Error fetching stock data: $e');
      return null;
    }
  }
  
  /// Fetch crypto data from API
  Future<MarketData?> _fetchCryptoData(String symbol) async {
    try {
      // Convert symbol to CoinGecko ID (simplified mapping)
      final coinId = _getCoinGeckoId(symbol);
      
      final response = await _dio.get(
        '$_cryptoApiUrl/coins/markets',
        queryParameters: {
          'vs_currency': 'usd',
          'ids': coinId,
          'order': 'market_cap_desc',
          'per_page': 1,
          'page': 1,
          'sparkline': false,
        },
      );
      
      if (response.statusCode == 200 && response.data.isNotEmpty) {
        final data = response.data[0];
        final marketData = MarketData(
          symbol: symbol,
          price: data['current_price'].toDouble(),
          previousClose: data['current_price'].toDouble() - 
                        (data['price_change_24h'] ?? 0).toDouble(),
          dayHigh: data['high_24h'].toDouble(),
          dayLow: data['low_24h'].toDouble(),
          volume: data['total_volume'].toDouble(),
          marketCap: data['market_cap'].toDouble(),
          peRatio: 0, // Not applicable for crypto
          dividendYield: 0,
          week52High: data['ath'].toDouble(),
          week52Low: data['atl'].toDouble(),
          timestamp: DateTime.now(),
          additionalData: {
            'price_change_24h': data['price_change_24h'],
            'price_change_percentage_24h': data['price_change_percentage_24h'],
            'circulating_supply': data['circulating_supply'],
            'total_supply': data['total_supply'],
          },
        );
        
        _marketDataCache[symbol] = marketData;
        _marketDataStreamController.add(marketData);
        return marketData;
      }
      
      return null;
    } catch (e) {
      print('Error fetching crypto data: $e');
      return null;
    }
  }
  
  /// Get CoinGecko ID from symbol
  String _getCoinGeckoId(String symbol) {
    // Common mappings
    final mappings = {
      'BTC': 'bitcoin',
      'ETH': 'ethereum',
      'BNB': 'binancecoin',
      'ADA': 'cardano',
      'DOGE': 'dogecoin',
      'XRP': 'ripple',
      'DOT': 'polkadot',
      'UNI': 'uniswap',
      'BCH': 'bitcoin-cash',
      'LTC': 'litecoin',
      'SOL': 'solana',
      'LINK': 'chainlink',
      'MATIC': 'matic-network',
      'AVAX': 'avalanche-2',
      'ATOM': 'cosmos',
    };
    
    return mappings[symbol.toUpperCase()] ?? symbol.toLowerCase();
  }
  
  /// Refresh market data for all portfolio items
  Future<void> _refreshMarketData() async {
    for (final portfolio in _portfolioCache.values) {
      if (!portfolio.isActive) continue;
      
      for (final item in portfolio.items) {
        // Check if we need to update
        final lastUpdate = _lastUpdateTime[item.symbol];
        if (lastUpdate != null && 
            DateTime.now().difference(lastUpdate).inMinutes < 5) {
          continue;
        }
        
        final marketData = await _fetchMarketData(item.symbol, item.type);
        if (marketData != null) {
          _lastUpdateTime[item.symbol] = DateTime.now();
          
          // Update portfolio with new prices
          await _updatePortfolioWithMarketData(portfolio, marketData);
        }
      }
    }
  }
  
  /// Update portfolio values with latest market data
  Future<void> _updatePortfolioWithMarketData(
    Portfolio portfolio,
    MarketData marketData,
  ) async {
    bool hasChanges = false;
    final updatedItems = portfolio.items.map((item) {
      if (item.symbol == marketData.symbol) {
        hasChanges = true;
        
        final newTotalValue = item.quantity * marketData.price;
        final gainLoss = newTotalValue - item.totalCost;
        final gainLossPercent = item.totalCost > 0 
            ? (gainLoss / item.totalCost) * 100 
            : 0.0;
        
        final dayChange = item.quantity * 
            (marketData.price - marketData.previousClose);
        final dayChangePercent = marketData.previousClose > 0
            ? ((marketData.price - marketData.previousClose) / 
               marketData.previousClose) * 100
            : 0.0;
        
        return item.copyWith(
          currentPrice: marketData.price,
          totalValue: newTotalValue,
          gainLoss: gainLoss,
          gainLossPercent: gainLossPercent,
          dayChange: dayChange,
          dayChangePercent: dayChangePercent,
          lastUpdated: DateTime.now(),
        );
      }
      return item;
    }).toList();
    
    if (hasChanges) {
      // Calculate portfolio totals
      double totalValue = 0;
      double totalCost = 0;
      double dayChange = 0;
      
      for (final item in updatedItems) {
        totalValue += item.totalValue;
        totalCost += item.totalCost;
        dayChange += item.dayChange;
      }
      
      final totalGainLoss = totalValue - totalCost;
      final totalGainLossPercent = totalCost > 0 
          ? (totalGainLoss / totalCost) * 100 
          : 0.0;
      final dayChangePercent = (totalValue - dayChange) > 0
          ? (dayChange / (totalValue - dayChange)) * 100
          : 0.0;
      
      final updatedPortfolio = portfolio.copyWith(
        items: updatedItems,
        totalValue: totalValue,
        totalCost: totalCost,
        totalGainLoss: totalGainLoss,
        totalGainLossPercent: totalGainLossPercent,
        dayChange: dayChange,
        dayChangePercent: dayChangePercent,
        updatedAt: DateTime.now(),
      );
      
      _portfolioCache[portfolio.id] = updatedPortfolio;
      _portfolioStreamController.add(updatedPortfolio);
      
      // Check alerts
      await _checkAlerts(updatedPortfolio);
    }
  }
  
  /// Check and trigger alerts
  Future<void> _checkAlerts(Portfolio portfolio) async {
    if (!portfolio.settings.enableAlerts) return;
    
    final alertRules = portfolio.settings.alertRules ?? {};
    
    for (final item in portfolio.items) {
      final itemAlerts = alertRules[item.symbol];
      if (itemAlerts == null) continue;
      
      // Check price alerts
      if (itemAlerts.type == AlertType.price_above &&
          item.currentPrice > itemAlerts.threshold) {
        _triggerAlert(PortfolioAlert(
          portfolioId: portfolio.id,
          itemId: item.id,
          symbol: item.symbol,
          alertRule: itemAlerts,
          currentValue: item.currentPrice,
          message: '${item.symbol} price is above \$${itemAlerts.threshold}',
          timestamp: DateTime.now(),
        ));
      }
      
      // Add more alert checks...
    }
  }
  
  /// Trigger an alert
  void _triggerAlert(PortfolioAlert alert) {
    _alertStreamController.add(alert);
    
    // TODO: Send push notification
    // TODO: Update alert last triggered time
  }
  
  /// Calculate portfolio performance
  Future<PortfolioPerformance> calculatePerformance(String portfolioId) async {
    final portfolio = await getPortfolio(portfolioId);
    if (portfolio == null) {
      throw Exception('Portfolio not found');
    }
    
    // Calculate sector allocation
    final sectorAllocation = <String, double>{};
    final assetAllocation = <String, double>{};
    
    for (final item in portfolio.items) {
      // Asset type allocation
      final assetType = item.type.toString();
      assetAllocation[assetType] = 
          (assetAllocation[assetType] ?? 0) + item.totalValue;
      
      // TODO: Add sector data from API
    }
    
    // Normalize allocations to percentages
    final totalValue = portfolio.totalValue;
    assetAllocation.forEach((key, value) {
      assetAllocation[key] = (value / totalValue) * 100;
    });
    
    // TODO: Load historical data from database
    final historicalData = <PerformancePoint>[];
    
    return PortfolioPerformance(
      portfolioId: portfolioId,
      date: DateTime.now(),
      totalValue: portfolio.totalValue,
      dayChange: portfolio.dayChange,
      dayChangePercent: portfolio.dayChangePercent,
      weekChange: 0, // TODO: Calculate from historical data
      weekChangePercent: 0,
      monthChange: 0,
      monthChangePercent: 0,
      yearChange: 0,
      yearChangePercent: 0,
      allTimeGainLoss: portfolio.totalGainLoss,
      allTimeGainLossPercent: portfolio.totalGainLossPercent,
      sectorAllocation: sectorAllocation,
      assetAllocation: assetAllocation,
      historicalData: historicalData,
    );
  }
  
  /// Save portfolio to database
  Future<void> _savePortfolio(Portfolio portfolio) async {
    // TODO: Implement database save
  }
  
  /// Delete portfolio
  Future<void> deletePortfolio(String portfolioId) async {
    _portfolioCache.remove(portfolioId);
    // TODO: Delete from database
  }
}

/// Portfolio alert model
class PortfolioAlert {
  final String portfolioId;
  final String itemId;
  final String symbol;
  final AlertRule alertRule;
  final double currentValue;
  final String message;
  final DateTime timestamp;
  
  PortfolioAlert({
    required this.portfolioId,
    required this.itemId,
    required this.symbol,
    required this.alertRule,
    required this.currentValue,
    required this.message,
    required this.timestamp,
  });
}