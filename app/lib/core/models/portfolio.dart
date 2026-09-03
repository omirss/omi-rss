import 'package:freezed_annotation/freezed_annotation.dart';

part 'portfolio.freezed.dart';
part 'portfolio.g.dart';

/// Portfolio model for tracking stocks, crypto, and other assets
@freezed
class Portfolio with _$Portfolio {
  const factory Portfolio({
    required String id,
    required String name,
    required String userId,
    required PortfolioType type,
    required DateTime createdAt,
    required DateTime updatedAt,
    required List<PortfolioItem> items,
    required PortfolioSettings settings,
    @Default(true) bool isActive,
    @Default(0.0) double totalValue,
    @Default(0.0) double totalCost,
    @Default(0.0) double totalGainLoss,
    @Default(0.0) double totalGainLossPercent,
    @Default(0.0) double dayChange,
    @Default(0.0) double dayChangePercent,
    Map<String, dynamic>? metadata,
  }) = _Portfolio;

  factory Portfolio.fromJson(Map<String, dynamic> json) =>
      _$PortfolioFromJson(json);
}

/// Individual portfolio item (stock, crypto, etc.)
@freezed
class PortfolioItem with _$PortfolioItem {
  const factory PortfolioItem({
    required String id,
    required String portfolioId,
    required String symbol,
    required String name,
    required AssetType type,
    required double quantity,
    required double averageCost,
    required double currentPrice,
    required DateTime purchaseDate,
    DateTime? lastUpdated,
    @Default(0.0) double totalValue,
    @Default(0.0) double totalCost,
    @Default(0.0) double gainLoss,
    @Default(0.0) double gainLossPercent,
    @Default(0.0) double dayChange,
    @Default(0.0) double dayChangePercent,
    @Default([]) List<Transaction> transactions,
    Map<String, dynamic>? metadata,
  }) = _PortfolioItem;

  factory PortfolioItem.fromJson(Map<String, dynamic> json) =>
      _$PortfolioItemFromJson(json);
}

/// Transaction record
@freezed
class Transaction with _$Transaction {
  const factory Transaction({
    required String id,
    required String portfolioItemId,
    required TransactionType type,
    required double quantity,
    required double price,
    required double totalAmount,
    required DateTime date,
    String? notes,
    Map<String, dynamic>? metadata,
  }) = _Transaction;

  factory Transaction.fromJson(Map<String, dynamic> json) =>
      _$TransactionFromJson(json);
}

/// Portfolio settings
@freezed
class PortfolioSettings with _$PortfolioSettings {
  const factory PortfolioSettings({
    @Default('USD') String currency,
    @Default(true) bool showInDashboard,
    @Default(true) bool enableAlerts,
    @Default(true) bool trackDividends,
    @Default(15) int refreshIntervalMinutes,
    @Default([]) List<String> watchlist,
    Map<String, AlertRule>? alertRules,
  }) = _PortfolioSettings;

  factory PortfolioSettings.fromJson(Map<String, dynamic> json) =>
      _$PortfolioSettingsFromJson(json);
}

/// Alert rule for portfolio items
@freezed
class AlertRule with _$AlertRule {
  const factory AlertRule({
    required String id,
    required String name,
    required AlertType type,
    required AlertCondition condition,
    required double threshold,
    @Default(true) bool isEnabled,
    DateTime? lastTriggered,
    @Default(0) int triggerCount,
  }) = _AlertRule;

  factory AlertRule.fromJson(Map<String, dynamic> json) =>
      _$AlertRuleFromJson(json);
}

/// Market data for real-time updates
@freezed
class MarketData with _$MarketData {
  const factory MarketData({
    required String symbol,
    required double price,
    required double previousClose,
    required double dayHigh,
    required double dayLow,
    required double volume,
    required double marketCap,
    required double peRatio,
    required double dividendYield,
    required double week52High,
    required double week52Low,
    required DateTime timestamp,
    Map<String, dynamic>? additionalData,
  }) = _MarketData;

  factory MarketData.fromJson(Map<String, dynamic> json) =>
      _$MarketDataFromJson(json);
}

/// Portfolio performance metrics
@freezed
class PortfolioPerformance with _$PortfolioPerformance {
  const factory PortfolioPerformance({
    required String portfolioId,
    required DateTime date,
    required double totalValue,
    required double dayChange,
    required double dayChangePercent,
    required double weekChange,
    required double weekChangePercent,
    required double monthChange,
    required double monthChangePercent,
    required double yearChange,
    required double yearChangePercent,
    required double allTimeGainLoss,
    required double allTimeGainLossPercent,
    required Map<String, double> sectorAllocation,
    required Map<String, double> assetAllocation,
    required List<PerformancePoint> historicalData,
  }) = _PortfolioPerformance;

  factory PortfolioPerformance.fromJson(Map<String, dynamic> json) =>
      _$PortfolioPerformanceFromJson(json);
}

/// Historical performance point
@freezed
class PerformancePoint with _$PerformancePoint {
  const factory PerformancePoint({
    required DateTime date,
    required double value,
    required double gainLoss,
    required double gainLossPercent,
  }) = _PerformancePoint;

  factory PerformancePoint.fromJson(Map<String, dynamic> json) =>
      _$PerformancePointFromJson(json);
}

// Enums
enum PortfolioType {
  stocks,
  crypto,
  mixed,
  watchlist,
}

enum AssetType {
  stock,
  crypto,
  etf,
  mutual_fund,
  bond,
  commodity,
  forex,
  other,
}

enum TransactionType {
  buy,
  sell,
  dividend,
  split,
  transfer_in,
  transfer_out,
}

enum AlertType {
  price_above,
  price_below,
  percent_change,
  volume_spike,
  new_high,
  new_low,
  earnings_announcement,
  dividend_announcement,
}

enum AlertCondition {
  greater_than,
  less_than,
  equals,
  crosses_above,
  crosses_below,
}