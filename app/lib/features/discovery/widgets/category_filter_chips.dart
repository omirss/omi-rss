import 'package:flutter/material.dart';
import '../discovery_service.dart';

class CategoryFilterChips extends StatelessWidget {
  final List<FeedCategory> categories;
  final String? selectedCategory;
  final Function(String?) onCategorySelected;

  const CategoryFilterChips({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selectedCategory == null,
            onSelected: (_) => onCategorySelected(null),
          ),
          const SizedBox(width: 8),
          ...categories.map((category) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(category.name),
                  selected: selectedCategory == category.id,
                  onSelected: (selected) {
                    onCategorySelected(selected ? category.id : null);
                  },
                ),
              )),
        ],
      ),
    );
  }
}