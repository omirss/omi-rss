import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/smart_market_service.dart';
import '../../providers/smart_market_provider.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';

/// Simple market price card
class MarketPriceCard extends ConsumerWidget {
  final String symbol;
  final VoidCallback? onTap;
  final bool compact;
  
  const MarketPriceCard({
    super.key,
    required this.symbol,
    this.onTap,
    this.compact = false,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = GlassTheme.of(context);
    final quoteAsync = ref.watch(marketQuoteProvider(symbol));
    
    return quoteAsync.when(
      data: (quote) {
        if (quote == null) {
          return const SizedBox.shrink();
        }
        
        return GestureDetector(
          onTap: onTap,
          child: compact
              ? _buildCompactCard(quote, theme)
              : _buildFullCard(quote, theme),
        );
      },
      loading: () => _buildLoadingCard(theme),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
  
  Widget _buildCompactCard(MarketQuote quote, GlassThemeData theme) {
    final color = quote.isPositive ? Colors.green : Colors.red;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quote.symbol,
            style: theme.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            quote.formattedPrice,
            style: theme.bodyMedium,
          ),
          const SizedBox(width: 4),
          Icon(
            quote.isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            color: color,
            size: 14,
          ),
          Text(
            quote.formattedChangePercent,
            style: theme.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFullCard(MarketQuote quote, GlassThemeData theme) {
    final color = quote.isPositive ? Colors.green : Colors.red;
    
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.symbol,
                      style: theme.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      quote.name,
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      quote.formattedPrice,
                      style: theme.titleLarge.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          quote.isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                          color: color,
                          size: 16,
                        ),
                        Text(
                          '${quote.formattedChange} (${quote.formattedChangePercent})',
                          style: theme.bodySmall.copyWith(
                            color: color,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('Day Range', '${quote.dayLow.toStringAsFixed(2)} - ${quote.dayHigh.toStringAsFixed(2)}', theme),
                _buildStat('Volume', _formatVolume(quote.volume), theme),
                if (quote.marketCap > 0)
                  _buildStat('Market Cap', _formatMarketCap(quote.marketCap), theme),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStat(String label, String value, GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.bodySmall.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        Text(
          value,
          style: theme.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildLoadingCard(GlassThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
  
  String _formatVolume(int volume) {
    if (volume >= 1000000000) {
      return '${(volume / 1000000000).toStringAsFixed(1)}B';
    } else if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(1)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(1)}K';
    }
    return volume.toString();
  }
  
  String _formatMarketCap(double cap) {
    if (cap >= 1000000000000) {
      return '\$${(cap / 1000000000000).toStringAsFixed(1)}T';
    } else if (cap >= 1000000000) {
      return '\$${(cap / 1000000000).toStringAsFixed(1)}B';
    } else if (cap >= 1000000) {
      return '\$${(cap / 1000000).toStringAsFixed(1)}M';
    }
    return '\$${cap.toStringAsFixed(0)}';
  }
}

/// Inline ticker widget for article content
class InlineTickerWidget extends ConsumerWidget {
  final String symbol;
  final Widget child;
  
  const InlineTickerWidget({
    super.key,
    required this.symbol,
    required this.child,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = GlassTheme.of(context);
    final quoteAsync = ref.watch(marketQuoteProvider(symbol));
    
    return GestureDetector(
      onTap: () => _showTickerPopup(context, ref, symbol),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.accentColor.withOpacity(0.5),
              width: 1,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
  
  void _showTickerPopup(BuildContext context, WidgetRef ref, String symbol) {
    final theme = GlassTheme.of(context);
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MarketQuotePopup(symbol: symbol),
          ),
        ),
      ),
    );
  }
}

/// Market quote popup
class MarketQuotePopup extends ConsumerWidget {
  final String symbol;
  
  const MarketQuotePopup({
    super.key,
    required this.symbol,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = GlassTheme.of(context);
    final quoteAsync = ref.watch(marketQuoteProvider(symbol));
    final watchlist = ref.watch(watchlistProvider);
    final isInWatchlist = watchlist.contains(symbol);
    
    return quoteAsync.when(
      data: (quote) {
        if (quote == null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Quote not available',
              style: theme.bodyMedium,
            ),
          );
        }
        
        final color = quote.isPositive ? Colors.green : Colors.red;
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quote.symbol,
                          style: theme.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          quote.name,
                          style: theme.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        quote.formattedPrice,
                        style: theme.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            quote.isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                            color: color,
                            size: 14,
                          ),
                          Text(
                            quote.formattedChangePercent,
                            style: theme.bodySmall.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Day Range',
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        '${quote.dayLow.toStringAsFixed(2)} - ${quote.dayHigh.toStringAsFixed(2)}',
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Volume',
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        _formatVolume(quote.volume),
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        if (isInWatchlist) {
                          ref.read(watchlistProvider.notifier).removeSymbol(symbol);
                        } else {
                          ref.read(watchlistProvider.notifier).addSymbol(symbol);
                        }
                        Navigator.of(context).pop();
                      },
                      icon: Icon(
                        isInWatchlist ? Icons.bookmark : Icons.bookmark_border,
                        color: theme.accentColor,
                      ),
                      label: Text(
                        isInWatchlist ? 'Remove from Watchlist' : 'Add to Watchlist',
                        style: TextStyle(color: theme.accentColor),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: theme.accentColor.withOpacity(0.1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Error loading quote',
          style: theme.bodyMedium,
        ),
      ),
    );
  }
  
  String _formatVolume(int volume) {
    if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(1)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(1)}K';
    }
    return volume.toString();
  }
}

/// Watchlist widget
class WatchlistWidget extends ConsumerWidget {
  final bool horizontal;
  final VoidCallback? onViewAll;
  
  const WatchlistWidget({
    super.key,
    this.horizontal = true,
    this.onViewAll,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = GlassTheme.of(context);
    final watchlist = ref.watch(watchlistProvider);
    
    if (watchlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 48,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'No stocks in watchlist',
              style: theme.bodyMedium.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }
    
    if (horizontal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Watchlist',
                style: theme.titleMedium,
              ),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: Text(
                    'View All',
                    style: TextStyle(color: theme.accentColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: watchlist.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return MarketPriceCard(
                  symbol: watchlist[index],
                  compact: true,
                );
              },
            ),
          ),
        ],
      );
    }
    
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: watchlist.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return MarketPriceCard(
          symbol: watchlist[index],
          compact: false,
        );
      },
    );
  }
}

/// Article content with inline tickers
class ArticleContentWithTickers extends ConsumerStatefulWidget {
  final String content;
  final TextStyle? style;
  
  const ArticleContentWithTickers({
    super.key,
    required this.content,
    this.style,
  });
  
  @override
  ConsumerState<ArticleContentWithTickers> createState() => _ArticleContentWithTickersState();
}

class _ArticleContentWithTickersState extends ConsumerState<ArticleContentWithTickers> {
  Map<String, MarketQuote>? _tickerData;
  
  @override
  void initState() {
    super.initState();
    _loadTickerData();
  }
  
  Future<void> _loadTickerData() async {
    final service = ref.read(smartMarketServiceProvider);
    final mentions = await service.getArticleMentions(widget.content);
    if (mounted) {
      setState(() {
        _tickerData = mentions;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_tickerData == null || _tickerData!.isEmpty) {
      return Text(
        widget.content,
        style: widget.style,
      );
    }
    
    // Build rich text with highlighted tickers
    final spans = <InlineSpan>[];
    var lastIndex = 0;
    
    // Find all ticker mentions
    final pattern = RegExp(r'\$?([A-Z]{1,5})\b');
    final matches = pattern.allMatches(widget.content);
    
    for (final match in matches) {
      final ticker = match.group(1)!;
      if (_tickerData!.containsKey(ticker)) {
        // Add text before ticker
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: widget.content.substring(lastIndex, match.start),
            style: widget.style,
          ));
        }
        
        // Add ticker widget
        final quote = _tickerData![ticker]!;
        final color = quote.isPositive ? Colors.green : Colors.red;
        
        spans.add(WidgetSpan(
          child: InlineTickerWidget(
            symbol: ticker,
            child: Text(
              match.group(0)!,
              style: (widget.style ?? const TextStyle()).copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ));
        
        lastIndex = match.end;
      }
    }
    
    // Add remaining text
    if (lastIndex < widget.content.length) {
      spans.add(TextSpan(
        text: widget.content.substring(lastIndex),
        style: widget.style,
      ));
    }
    
    return RichText(
      text: TextSpan(children: spans),
    );
  }
}