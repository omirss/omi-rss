import 'package:flutter/material.dart';
import '../analytics_service.dart';

class RecommendationsList extends StatelessWidget {
  final List<Recommendation> recommendations;
  final VoidCallback onRefresh;

  const RecommendationsList({
    super.key,
    required this.recommendations,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.recommend,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No recommendations yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Keep reading to get personalized recommendations',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: recommendations.length,
        itemBuilder: (context, index) {
          final recommendation = recommendations[index];
          return _RecommendationCard(recommendation: recommendation);
        },
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final Recommendation recommendation;

  const _RecommendationCard({
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIcon(context),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recommendation.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (recommendation.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            recommendation.description!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildScore(context),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      recommendation.reason,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              if (recommendation.metadata != null &&
                  recommendation.metadata!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _buildMetadataTags(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    IconData icon;
    Color color;

    switch (recommendation.type) {
      case 'article':
        icon = Icons.article;
        color = Theme.of(context).colorScheme.primary;
        break;
      case 'feed':
        icon = Icons.rss_feed;
        color = Theme.of(context).colorScheme.secondary;
        break;
      default:
        icon = Icons.recommend;
        color = Theme.of(context).colorScheme.tertiary;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildScore(BuildContext context) {
    final percentage = (recommendation.score * 100).toInt();
    final color = _getScoreColor(recommendation.score);

    return Column(
      children: [
        Text(
          '$percentage%',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          'Match',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
              ),
        ),
      ],
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 0.8) {
      return Colors.green;
    } else if (score >= 0.6) {
      return Colors.orange;
    } else {
      return Colors.grey;
    }
  }

  List<Widget> _buildMetadataTags(BuildContext context) {
    final tags = <Widget>[];
    final metadata = recommendation.metadata!;

    if (metadata['category'] != null) {
      tags.add(_buildTag(
        context,
        Icons.category,
        metadata['category'].toString(),
      ));
    }

    if (metadata['readTime'] != null) {
      tags.add(_buildTag(
        context,
        Icons.timer,
        '${metadata['readTime']} min',
      ));
    }

    if (metadata['author'] != null) {
      tags.add(_buildTag(
        context,
        Icons.person,
        metadata['author'].toString(),
      ));
    }

    if (metadata['date'] != null) {
      final date = DateTime.parse(metadata['date'].toString());
      final formattedDate = '${date.day}/${date.month}/${date.year}';
      tags.add(_buildTag(
        context,
        Icons.calendar_today,
        formattedDate,
      ));
    }

    return tags;
  }

  Widget _buildTag(BuildContext context, IconData icon, String label) {
    return Chip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _handleTap(BuildContext context) {
    // TODO: Navigate to article or feed based on type
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening ${recommendation.title}'),
      ),
    );
  }
}