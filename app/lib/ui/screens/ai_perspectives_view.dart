import 'package:flutter/material.dart';
import '../../core/services/ai_service.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';

/// AI Perspectives view component
class AIPerspectivesView extends StatefulWidget {
  final AIAnalysisResult result;
  
  const AIPerspectivesView({
    super.key,
    required this.result,
  });
  
  @override
  State<AIPerspectivesView> createState() => _AIPerspectivesViewState();
}

class _AIPerspectivesViewState extends State<AIPerspectivesView> {
  String? _selectedPerspective;
  bool _showComparison = false;
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final perspectives = widget.result.perspectives;
    
    if (perspectives == null || perspectives.perspectives.isEmpty) {
      return Center(
        child: Text(
          'No perspectives analysis available',
          style: theme.bodyLarge.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPrimaryStance(perspectives, theme),
          const SizedBox(height: 24),
          _buildControls(theme),
          const SizedBox(height: 16),
          if (_showComparison)
            _buildComparisonView(perspectives, theme)
          else
            _buildPerspectiveGrid(perspectives, theme),
        ],
      ),
    );
  }
  
  Widget _buildPrimaryStance(MultiPerspective perspectives, GlassThemeData theme) {
    final stance = perspectives.primaryStance;
    
    return GlassCard(
      theme: theme,
      borderColor: theme.accentColor.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.article,
                  color: theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Article\'s Primary Stance',
                  style: theme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (stance['political_leaning'] != null) ...[
              _buildStanceItem(
                'Political Leaning',
                stance['political_leaning'],
                _getPoliticalColor(stance['political_leaning']),
                theme,
              ),
            ],
            if (stance['viewpoint'] != null) ...[
              const SizedBox(height: 8),
              _buildStanceItem(
                'Viewpoint',
                stance['viewpoint'],
                Colors.purple,
                theme,
              ),
            ],
            if (stance['assumptions'] != null) ...[
              const SizedBox(height: 12),
              Text(
                'Key Assumptions:',
                style: theme.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              ...(stance['assumptions'] as List).map((assumption) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: theme.bodyMedium),
                      Expanded(
                        child: Text(
                          assumption.toString(),
                          style: theme.bodyMedium.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildControls(GlassThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Alternative Perspectives',
          style: theme.titleLarge,
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                _showComparison ? Icons.grid_view : Icons.compare_arrows,
                color: theme.accentColor,
              ),
              onPressed: () => setState(() => _showComparison = !_showComparison),
              tooltip: _showComparison ? 'Grid View' : 'Comparison View',
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildPerspectiveGrid(MultiPerspective perspectives, GlassThemeData theme) {
    final perspectiveList = perspectives.perspectives.entries.toList();
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: perspectiveList.length,
      itemBuilder: (context, index) {
        final entry = perspectiveList[index];
        final type = entry.key;
        final perspective = entry.value;
        
        return _buildPerspectiveCard(type, perspective, theme);
      },
    );
  }
  
  Widget _buildPerspectiveCard(
    String type,
    PerspectiveSummary perspective,
    GlassThemeData theme,
  ) {
    final isSelected = _selectedPerspective == type;
    final color = _getPerspectiveColor(type);
    
    return GestureDetector(
      onTap: () => setState(() {
        _selectedPerspective = isSelected ? null : type;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: GlassCard(
          theme: theme,
          borderColor: isSelected ? color.withOpacity(0.5) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getPerspectiveIcon(type),
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatPerspectiveType(type),
                        style: theme.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (perspective.confidence > 0) ...[
                  LinearProgressIndicator(
                    value: perspective.confidence,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      color.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      perspective.summary,
                      style: theme.bodySmall.copyWith(
                        height: 1.4,
                      ),
                      maxLines: isSelected ? null : 6,
                      overflow: isSelected ? null : TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (isSelected && perspective.keyPoints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Key Points:',
                          style: theme.bodySmall.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...perspective.keyPoints.map((point) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '• $point',
                            style: theme.bodySmall.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        )).toList(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildComparisonView(MultiPerspective perspectives, GlassThemeData theme) {
    return Column(
      children: [
        if (_selectedPerspective != null) ...[
          GlassCard(
            theme: theme,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comparing: ${_formatPerspectiveType(_selectedPerspective!)}',
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  _buildComparisonTable(perspectives, theme),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildPerspectiveSelector(perspectives, theme),
      ],
    );
  }
  
  Widget _buildComparisonTable(MultiPerspective perspectives, GlassThemeData theme) {
    if (_selectedPerspective == null) return const SizedBox.shrink();
    
    final selected = perspectives.perspectives[_selectedPerspective!];
    if (selected == null) return const SizedBox.shrink();
    
    final originalStance = perspectives.primaryStance;
    
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
      },
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Original',
                style: theme.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getPerspectiveColor(_selectedPerspective!).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatPerspectiveType(_selectedPerspective!),
                style: theme.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _getPerspectiveColor(_selectedPerspective!),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        _buildComparisonRow(
          'Viewpoint',
          originalStance['viewpoint'] ?? 'Not specified',
          _selectedPerspective!,
          theme,
        ),
        _buildComparisonRow(
          'Key Focus',
          'Original article focus',
          selected.keyPoints.isNotEmpty ? selected.keyPoints.first : 'N/A',
          theme,
        ),
        _buildComparisonRow(
          'Confidence',
          '100%',
          '${(selected.confidence * 100).toStringAsFixed(0)}%',
          theme,
        ),
      ],
    );
  }
  
  TableRow _buildComparisonRow(
    String label,
    String original,
    String alternative,
    GlassThemeData theme,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            label,
            style: theme.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            original,
            style: theme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            alternative,
            style: theme.bodySmall,
          ),
        ),
      ],
    );
  }
  
  Widget _buildPerspectiveSelector(MultiPerspective perspectives, GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Perspective to Compare',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: perspectives.perspectives.keys.map((type) {
                final isSelected = _selectedPerspective == type;
                final color = _getPerspectiveColor(type);
                
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedPerspective = isSelected ? null : type;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? color.withOpacity(0.5)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getPerspectiveIcon(type),
                          color: isSelected ? color : Colors.white.withOpacity(0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatPerspectiveType(type),
                          style: theme.bodySmall.copyWith(
                            color: isSelected ? color : Colors.white.withOpacity(0.7),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStanceItem(
    String label,
    String value,
    Color color,
    GlassThemeData theme,
  ) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.bodyMedium.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        Text(
          value,
          style: theme.bodyMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
  
  Color _getPoliticalColor(String leaning) {
    switch (leaning.toLowerCase()) {
      case 'left':
      case 'liberal':
        return Colors.blue;
      case 'center':
      case 'centrist':
        return Colors.purple;
      case 'right':
      case 'conservative':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  Color _getPerspectiveColor(String type) {
    switch (type) {
      case 'conservative':
        return Colors.red;
      case 'liberal':
        return Colors.blue;
      case 'libertarian':
        return Colors.yellow;
      case 'socialist':
        return Colors.pink;
      case 'centrist':
        return Colors.purple;
      case 'international':
        return Colors.teal;
      case 'historical':
        return Colors.brown;
      case 'future_implications':
        return Colors.indigo;
      case 'economic':
        return Colors.green;
      case 'environmental':
        return Colors.lightGreen;
      case 'social_justice':
        return Colors.orange;
      case 'scientific':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getPerspectiveIcon(String type) {
    switch (type) {
      case 'conservative':
        return Icons.account_balance;
      case 'liberal':
        return Icons.people;
      case 'libertarian':
        return Icons.accessibility_new;
      case 'socialist':
        return Icons.groups;
      case 'centrist':
        return Icons.balance;
      case 'international':
        return Icons.public;
      case 'historical':
        return Icons.history;
      case 'future_implications':
        return Icons.rocket_launch;
      case 'economic':
        return Icons.attach_money;
      case 'environmental':
        return Icons.eco;
      case 'social_justice':
        return Icons.gavel;
      case 'scientific':
        return Icons.science;
      default:
        return Icons.lens;
    }
  }
  
  String _formatPerspectiveType(String type) {
    return type.replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.substring(0, 1).toUpperCase() + word.substring(1))
        .join(' ');
  }
}