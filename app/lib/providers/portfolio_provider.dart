import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../core/models/portfolio.dart';
import '../core/services/portfolio_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

part 'portfolio_provider.g.dart';

/// Provider for portfolio service
@riverpod
PortfolioService portfolioService(PortfolioServiceRef ref) {
  final database = ref.watch(databaseProvider);
  final settingsService = ref.watch(settingsServiceProvider);
  
  final service = PortfolioService(
    database: database,
    settingsService: settingsService,
  );
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
}

/// Provider for all portfolios
@riverpod
Future<List<Portfolio>> portfolios(PortfoliosRef ref) async {
  final service = ref.watch(portfolioServiceProvider);
  return service.getPortfolios();
}

/// Provider for a specific portfolio
@riverpod
Future<Portfolio?> portfolio(PortfolioRef ref, String portfolioId) async {
  final service = ref.watch(portfolioServiceProvider);
  return service.getPortfolio(portfolioId);
}

/// Provider for portfolio performance
@riverpod
Future<PortfolioPerformance> portfolioPerformance(
  PortfolioPerformanceRef ref,
  String portfolioId,
) async {
  final service = ref.watch(portfolioServiceProvider);
  return service.calculatePerformance(portfolioId);
}

/// Provider for real-time portfolio updates
@riverpod
Stream<Portfolio> portfolioStream(PortfolioStreamRef ref) {
  final service = ref.watch(portfolioServiceProvider);
  return service.portfolioStream;
}

/// Provider for market data updates
@riverpod
Stream<MarketData> marketDataStream(MarketDataStreamRef ref) {
  final service = ref.watch(portfolioServiceProvider);
  return service.marketDataStream;
}

/// Provider for portfolio alerts
@riverpod
Stream<PortfolioAlert> portfolioAlertStream(PortfolioAlertStreamRef ref) {
  final service = ref.watch(portfolioServiceProvider);
  return service.alertStream;
}

/// Provider for total portfolio value across all portfolios
@riverpod
Future<double> totalPortfolioValue(TotalPortfolioValueRef ref) async {
  final portfolios = await ref.watch(portfoliosProvider.future);
  return portfolios.fold(0.0, (sum, portfolio) => sum + portfolio.totalValue);
}

/// Provider for portfolio statistics
@riverpod
Future<PortfolioStatistics> portfolioStatistics(PortfolioStatisticsRef ref) async {
  final portfolios = await ref.watch(portfoliosProvider.future);
  
  double totalValue = 0;
  double totalGainLoss = 0;
  double dayChange = 0;
  int totalItems = 0;
  
  for (final portfolio in portfolios) {
    totalValue += portfolio.totalValue;
    totalGainLoss += portfolio.totalGainLoss;
    dayChange += portfolio.dayChange;
    totalItems += portfolio.items.length;
  }
  
  final totalGainLossPercent = totalValue > 0 
      ? (totalGainLoss / (totalValue - totalGainLoss)) * 100 
      : 0.0;
  final dayChangePercent = (totalValue - dayChange) > 0
      ? (dayChange / (totalValue - dayChange)) * 100
      : 0.0;
  
  // Calculate best and worst performers
  final allItems = portfolios.expand((p) => p.items).toList();
  allItems.sort((a, b) => b.gainLossPercent.compareTo(a.gainLossPercent));
  
  return PortfolioStatistics(
    totalValue: totalValue,
    totalGainLoss: totalGainLoss,
    totalGainLossPercent: totalGainLossPercent,
    dayChange: dayChange,
    dayChangePercent: dayChangePercent,
    portfolioCount: portfolios.length,
    totalItems: totalItems,
    bestPerformer: allItems.isNotEmpty ? allItems.first : null,
    worstPerformer: allItems.isNotEmpty ? allItems.last : null,
  );
}

/// Portfolio statistics model
class PortfolioStatistics {
  final double totalValue;
  final double totalGainLoss;
  final double totalGainLossPercent;
  final double dayChange;
  final double dayChangePercent;
  final int portfolioCount;
  final int totalItems;
  final PortfolioItem? bestPerformer;
  final PortfolioItem? worstPerformer;
  
  PortfolioStatistics({
    required this.totalValue,
    required this.totalGainLoss,
    required this.totalGainLossPercent,
    required this.dayChange,
    required this.dayChangePercent,
    required this.portfolioCount,
    required this.totalItems,
    this.bestPerformer,
    this.worstPerformer,
  });
}