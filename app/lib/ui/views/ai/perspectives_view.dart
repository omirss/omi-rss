import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ai_service.dart';
import '../../components/glass_container.dart';
import '../../glass_theme.dart';

/// View for displaying multiple perspectives on an article
class PerspectivesView extends ConsumerStatefulWidget {
  final MultiPerspective perspectives;
  final VoidCallback onClose;
  
  const PerspectivesView({
    super.key,
    required this.perspectives,
    required this.onClose,
  });
  
  @override
  ConsumerState<PerspectivesView> createState() => _PerspectivesViewState();
}

class _PerspectivesViewState extends ConsumerState<PerspectivesView>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPerspective = 'conservative';
  
  final Map<String, IconData> _perspectiveIcons = {
    'conservative': Icons.account_balance,
    'liberal': Icons.account_tree,
    'libertarian': Icons.trending_up,
    'socialist': Icons.people,
    'centrist': Icons.adjust,
    'international': Icons.public,
    'historical': Icons.history,
    'future_implications': Icons.rocket_launch,
    'economic': Icons.attach_money,
    'environmental': Icons.eco,
    'social_justice': Icons.balance,
    'scientific': Icons.science,
  };
  
  final Map<String, Color> _perspectiveColors = {
    'conservative': Colors.blue,
    'liberal': Colors.red,
    'libertarian': Colors.amber,
    'socialist': Colors.purple,
    'centrist': Colors.grey,
    'international': Colors.teal,
    'historical': Colors.brown,
    'future_implications': Colors.indigo,
    'economic': Colors.green,
    'environmental': Colors.lightGreen,
    'social_justice': Colors.orange,
    'scientific': Colors.cyan,
  };
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.perspectives.perspectives.length,
      vsync: this,
    );
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(glassThemeProvider);
    
    return GlassContainer(
      blur: theme.blur,
      opacity: theme.opacity,
      gradient: LinearGradient(
        colors: theme.gradientColors,
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: theme.borderColor,
        width: theme.borderWidth,
      ),
      shadows: theme.shadows,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.borderColor.withOpacity(0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.psychology,
                  color: theme.textColor,
                  size: 28,
                ).animate().scale(
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multiple Perspectives',
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'View this article from different viewpoints',
                        style: TextStyle(
                          color: theme.textColor.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: theme.textColor.withOpacity(0.7),
                  ),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          
          // Primary Stance
          if (widget.perspectives.primaryStance.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.3),
                border: Border(
                  bottom: BorderSide(
                    color: theme.borderColor.withOpacity(0.3),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Primary Article Stance',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.perspectives.primaryStance['political'] != null)
                        _buildStanceChip(
                          'Political: ${widget.perspectives.primaryStance['political']}',
                          Icons.how_to_vote,
                          Colors.blue,
                        ),
                      if (widget.perspectives.primaryStance['viewpoint'] != null)
                        _buildStanceChip(
                          widget.perspectives.primaryStance['viewpoint'],
                          Icons.visibility,
                          Colors.purple,
                        ),
                      if (widget.perspectives.primaryStance['cultural'] != null)
                        _buildStanceChip(
                          'Cultural: ${widget.perspectives.primaryStance['cultural']}',
                          Icons.diversity_3,
                          Colors.orange,
                        ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms),
          ],
          
          // Perspective Selector
          Container(
            height: 120,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.perspectives.perspectives.length,
              itemBuilder: (context, index) {
                final type = widget.perspectives.perspectives.keys.elementAt(index);
                final isSelected = type == _selectedPerspective;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildPerspectiveCard(
                    type,
                    isSelected,
                    () => setState(() => _selectedPerspective = type),
                  ),
                );
              },
            ),
          ),
          
          // Selected Perspective Content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildPerspectiveContent(
                widget.perspectives.perspectives[_selectedPerspective]!,
              ),
            ),
          ),
          
          // Related Articles
          if (widget.perspectives.relatedArticles.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.borderColor.withOpacity(0.3),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Related Perspectives',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...widget.perspectives.relatedArticles.take(3).map(
                    (article) => _buildRelatedArticle(article),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildStanceChip(String label, IconData icon, Color color) {
    final theme = ref.watch(glassThemeProvider);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPerspectiveCard(String type, bool isSelected, VoidCallback onTap) {
    final theme = ref.watch(glassThemeProvider);
    final icon = _perspectiveIcons[type] ?? Icons.lens;
    final color = _perspectiveColors[type] ?? Colors.grey;
    final label = type.replaceAll('_', ' ').split(' ').map((word) =>
      word[0].toUpperCase() + word.substring(1)
    ).join(' ');
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.3)
              : theme.cardColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color
                : theme.borderColor.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : theme.textColor.withOpacity(0.7),
              size: 28,
            ).animate(target: isSelected ? 1 : 0).scale(
              end: const Offset(1.2, 1.2),
              duration: 200.ms,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ).animate()
      .fadeIn(delay: (type.hashCode % 12) * 50.ms)
      .slideX(
        begin: 0.2,
        duration: 400.ms,
        curve: Curves.easeOutBack,
      );
  }
  
  Widget _buildPerspectiveContent(PerspectiveSummary perspective) {
    final theme = ref.watch(glassThemeProvider);
    final color = _perspectiveColors[perspective.type] ?? Colors.grey;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _perspectiveIcons[perspective.type] ?? Icons.lens,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Summary',
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(perspective.confidence * 100).toInt()}% confidence',
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  perspective.summary,
                  style: TextStyle(
                    color: theme.textColor.withOpacity(0.9),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
          
          const SizedBox(height: 20),
          
          // Key Points
          if (perspective.keyPoints.isNotEmpty) ...[
            Text(
              'Key Points',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...perspective.keyPoints.asMap().entries.map((entry) {
              final index = entry.key;
              final point = entry.value;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.borderColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(
                          color: theme.textColor.withOpacity(0.9),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate()
                .fadeIn(delay: (index * 100).ms)
                .slideX(begin: -0.1);
            }),
          ],
        ],
      ),
    );
  }
  
  Widget _buildRelatedArticle(RelatedPerspective article) {
    final theme = ref.watch(glassThemeProvider);
    final color = _perspectiveColors[article.perspectiveType] ?? Colors.grey;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // TODO: Open article
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.borderColor.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(
                      _perspectiveIcons[article.perspectiveType] ?? Icons.lens,
                      color: color,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${article.source} • ${(article.relevance * 100).toInt()}% relevant',
                        style: TextStyle(
                          color: theme.textColor.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: theme.textColor.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}