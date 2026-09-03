import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../providers/feed_provider.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_button.dart';
import 'search_service.dart';

class SearchFiltersSheet extends ConsumerStatefulWidget {
  const SearchFiltersSheet({super.key});
  
  @override
  ConsumerState<SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class _SearchFiltersSheetState extends ConsumerState<SearchFiltersSheet> {
  late SearchFilters _filters;
  final Set<String> _selectedFeedIds = {};
  DateTime? _dateFrom;
  DateTime? _dateTo;
  
  @override
  void initState() {
    super.initState();
    _filters = ref.read(searchProvider).filters;
    _selectedFeedIds.addAll(_filters.feedIds ?? []);
    _dateFrom = _filters.dateFrom;
    _dateTo = _filters.dateTo;
  }
  
  @override
  Widget build(BuildContext context) {
    final feeds = ref.watch(feedsProvider);
    
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Title
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Search Filters',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // Filter options
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Read status
                    _buildSectionTitle('Read Status'),
                    Row(
                      children: [
                        Expanded(
                          child: _buildOptionChip(
                            'All',
                            _filters.isRead == null,
                            () => setState(() => _filters = _filters.copyWith(
                              isRead: null,
                            )),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildOptionChip(
                            'Unread',
                            _filters.isRead == false,
                            () => setState(() => _filters = _filters.copyWith(
                              isRead: false,
                            )),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildOptionChip(
                            'Read',
                            _filters.isRead == true,
                            () => setState(() => _filters = _filters.copyWith(
                              isRead: true,
                            )),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Starred
                    SwitchListTile(
                      title: Text(
                        'Starred only',
                        style: TextStyle(color: Colors.white.withOpacity(0.9)),
                      ),
                      value: _filters.isStarred ?? false,
                      onChanged: (value) {
                        setState(() => _filters = _filters.copyWith(
                          isStarred: value ? true : null,
                        ));
                      },
                      activeColor: GlassTheme.primaryColor,
                    ),
                    
                    // Has annotations
                    SwitchListTile(
                      title: Text(
                        'Has annotations',
                        style: TextStyle(color: Colors.white.withOpacity(0.9)),
                      ),
                      value: _filters.hasAnnotations ?? false,
                      onChanged: (value) {
                        setState(() => _filters = _filters.copyWith(
                          hasAnnotations: value ? true : null,
                        ));
                      },
                      activeColor: GlassTheme.primaryColor,
                    ),
                    const SizedBox(height: 24),
                    
                    // Date range
                    _buildSectionTitle('Date Range'),
                    Row(
                      children: [
                        Expanded(
                          child: GlassButton(
                            text: _dateFrom != null
                              ? _formatDate(_dateFrom!)
                              : 'From date',
                            icon: Icons.calendar_today,
                            onPressed: () => _selectDate(true),
                            variant: GlassButtonVariant.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GlassButton(
                            text: _dateTo != null
                              ? _formatDate(_dateTo!)
                              : 'To date',
                            icon: Icons.calendar_today,
                            onPressed: () => _selectDate(false),
                            variant: GlassButtonVariant.text,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Feeds
                    _buildSectionTitle('Feeds'),
                    feeds.when(
                      data: (feedList) => Column(
                        children: feedList.map((feed) => 
                          CheckboxListTile(
                            title: Text(
                              feed.title,
                              style: TextStyle(color: Colors.white.withOpacity(0.9)),
                            ),
                            subtitle: Text(
                              '${feed.itemCount} articles',
                              style: TextStyle(color: Colors.white.withOpacity(0.6)),
                            ),
                            value: _selectedFeedIds.contains(feed.id),
                            onChanged: (value) {
                              setState(() {
                                if (value ?? false) {
                                  _selectedFeedIds.add(feed.id);
                                } else {
                                  _selectedFeedIds.remove(feed.id);
                                }
                              });
                            },
                            activeColor: GlassTheme.primaryColor,
                            checkColor: Colors.white,
                          ),
                        ).toList(),
                      ),
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      error: (_, __) => Text(
                        'Failed to load feeds',
                        style: TextStyle(color: Colors.red.shade300),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Minimum score
                    _buildSectionTitle('Minimum Score'),
                    Slider(
                      value: (_filters.minScore ?? 0) * 100,
                      min: 0,
                      max: 100,
                      divisions: 10,
                      label: '${((_filters.minScore ?? 0) * 100).round()}%',
                      onChanged: (value) {
                        setState(() => _filters = _filters.copyWith(
                          minScore: value > 0 ? value / 100 : null,
                        ));
                      },
                      activeColor: GlassTheme.primaryColor,
                      inactiveColor: Colors.white.withOpacity(0.2),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              
              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        text: 'Clear All',
                        onPressed: () {
                          setState(() {
                            _filters = SearchFilters();
                            _selectedFeedIds.clear();
                            _dateFrom = null;
                            _dateTo = null;
                          });
                        },
                        variant: GlassButtonVariant.text,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GlassButton(
                        text: 'Apply',
                        onPressed: () {
                          // Update filters with selected feeds and dates
                          final updatedFilters = _filters.copyWith(
                            feedIds: _selectedFeedIds.isNotEmpty
                              ? _selectedFeedIds.toList()
                              : null,
                            dateFrom: _dateFrom,
                            dateTo: _dateTo,
                          );
                          
                          ref.read(searchProvider.notifier).updateFilters(updatedFilters);
                          Navigator.pop(context);
                        },
                        variant: GlassButtonVariant.elevated,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.7),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
  
  Widget _buildOptionChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
            ? GlassTheme.primaryColor.withOpacity(0.3)
            : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
              ? GlassTheme.primaryColor
              : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _selectDate(bool isFrom) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_dateFrom ?? now) : (_dateTo ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6200EE),
              surface: Color(0xFF1E1E1E),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (selected != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = selected;
        } else {
          _dateTo = selected;
        }
      });
    }
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Extension to make filters copyable
extension _SearchFiltersCopyWith on SearchFilters {
  SearchFilters copyWith({
    List<String>? feedIds,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isRead,
    bool? isStarred,
    bool? hasAnnotations,
    List<String>? categories,
    double? minScore,
  }) {
    return SearchFilters(
      feedIds: feedIds ?? this.feedIds,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      isRead: isRead,
      isStarred: isStarred,
      hasAnnotations: hasAnnotations,
      categories: categories ?? this.categories,
      minScore: minScore,
    );
  }
}