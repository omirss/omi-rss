import 'package:flutter/material.dart';
import 'dart:async';
import '../analytics_service.dart';

class InsightsCarousel extends StatefulWidget {
  final List<Insight> insights;

  const InsightsCarousel({
    super.key,
    required this.insights,
  });

  @override
  State<InsightsCarousel> createState() => _InsightsCarouselState();
}

class _InsightsCarouselState extends State<InsightsCarousel> {
  final PageController _pageController = PageController();
  Timer? _autoScrollTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPage < widget.insights.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: widget.insights.length,
            itemBuilder: (context, index) {
              final insight = widget.insights[index];
              return _InsightCard(insight: insight);
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.insights.length,
            (index) => Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Insight insight;

  const _InsightCard({
    required this.insight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        child: InkWell(
          onTap: insight.actionUrl != null ? () => _handleAction(context) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildIcon(context),
                const SizedBox(height: 16),
                Text(
                  insight.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  insight.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (insight.data != null) ...[
                  const SizedBox(height: 24),
                  _buildDataVisualization(context),
                ],
                if (insight.actionUrl != null) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _handleAction(context),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Take Action'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    IconData icon;
    Color color;

    switch (insight.type) {
      case 'achievement':
        icon = Icons.emoji_events;
        color = Colors.amber;
        break;
      case 'trend':
        icon = Icons.trending_up;
        color = Colors.green;
        break;
      case 'recommendation':
        icon = Icons.lightbulb;
        color = Theme.of(context).colorScheme.primary;
        break;
      case 'milestone':
        icon = Icons.flag;
        color = Theme.of(context).colorScheme.secondary;
        break;
      case 'warning':
        icon = Icons.warning;
        color = Colors.orange;
        break;
      default:
        icon = Icons.insights;
        color = Theme.of(context).colorScheme.tertiary;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 48,
        color: color,
      ),
    );
  }

  Widget _buildDataVisualization(BuildContext context) {
    final data = insight.data!;

    // Check if data contains percentage
    if (data['percentage'] != null) {
      final percentage = data['percentage'] as double;
      return Column(
        children: [
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 8,
              backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      );
    }

    // Check if data contains comparison
    if (data['current'] != null && data['previous'] != null) {
      final current = data['current'];
      final previous = data['previous'];
      final change = ((current - previous) / previous * 100).toStringAsFixed(1);
      final isPositive = current > previous;

      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(
                'Current',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                current.toString(),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(width: 32),
          Icon(
            isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            color: isPositive ? Colors.green : Colors.red,
            size: 32,
          ),
          const SizedBox(width: 8),
          Text(
            '$change%',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: isPositive ? Colors.green : Colors.red,
                ),
          ),
        ],
      );
    }

    // Check if data contains list
    if (data['items'] != null && data['items'] is List) {
      final items = data['items'] as List;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .take(5)
            .map((item) => Chip(
                  label: Text(item.toString()),
                  visualDensity: VisualDensity.compact,
                ))
            .toList(),
      );
    }

    // Default: show as key-value pairs
    return Column(
      children: data.entries
          .take(3)
          .map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${entry.key}: ',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      entry.value.toString(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  void _handleAction(BuildContext context) {
    // TODO: Navigate based on actionUrl
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Action: ${insight.actionUrl}'),
      ),
    );
  }
}