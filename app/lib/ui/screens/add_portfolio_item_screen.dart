import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/portfolio.dart';
import '../../providers/portfolio_provider.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_text_field.dart';

/// Screen for adding items to portfolio
class AddPortfolioItemScreen extends ConsumerStatefulWidget {
  final Portfolio portfolio;
  
  const AddPortfolioItemScreen({
    super.key,
    required this.portfolio,
  });
  
  @override
  ConsumerState<AddPortfolioItemScreen> createState() => _AddPortfolioItemScreenState();
}

class _AddPortfolioItemScreenState extends ConsumerState<AddPortfolioItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _symbolController = TextEditingController();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  
  AssetType _selectedType = AssetType.stock;
  DateTime _purchaseDate = DateTime.now();
  bool _isLoading = false;
  
  @override
  void dispose() {
    _symbolController.dispose();
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Add to Portfolio'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Portfolio info
            GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adding to:',
                    style: theme.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.portfolio.name,
                    style: theme.titleMedium,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Asset type selector
            GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Asset Type',
                    style: theme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: AssetType.values.map((type) {
                      final isSelected = type == _selectedType;
                      return ChoiceChip(
                        label: Text(
                          type.toString().split('.').last.replaceAll('_', ' ').toUpperCase(),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedType = type);
                          }
                        },
                        selectedColor: theme.primaryColor,
                        backgroundColor: Colors.white.withOpacity(0.1),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Symbol input
            GlassTextField(
              controller: _symbolController,
              labelText: 'Symbol/Ticker',
              hintText: _selectedType == AssetType.crypto ? 'e.g., BTC' : 'e.g., AAPL',
            ),
            
            const SizedBox(height: 16),
            
            // Name input
            GlassTextField(
              controller: _nameController,
              labelText: 'Name (Optional)',
              hintText: 'e.g., Apple Inc.',
            ),
            
            const SizedBox(height: 16),
            
            // Quantity and price
            Row(
              children: [
                Expanded(
                  child: GlassTextField(
                    controller: _quantityController,
                    labelText: 'Quantity',
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassTextField(
                    controller: _priceController,
                    labelText: 'Price per Unit',
                    hintText: '0.00',
                    prefixIcon: Icons.attach_money,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Purchase date
            GlassContainer(
              onTap: _selectDate,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Purchase Date',
                          style: theme.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(_purchaseDate),
                          style: theme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Total cost preview
            if (_quantityController.text.isNotEmpty && _priceController.text.isNotEmpty)
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Cost',
                      style: theme.titleSmall,
                    ),
                    Text(
                      '\$${_calculateTotalCost()}',
                      style: theme.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 32),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    text: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                    variant: GlassButtonVariant.outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassButton(
                    text: 'Add to Portfolio',
                    onPressed: _isLoading ? null : _addToPortfolio,
                    variant: GlassButtonVariant.elevated,
                    isLoading: _isLoading,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.purple,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _purchaseDate) {
      setState(() {
        _purchaseDate = picked;
      });
    }
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
  
  String _calculateTotalCost() {
    final quantity = double.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0;
    return (quantity * price).toStringAsFixed(2);
  }
  
  Future<void> _addToPortfolio() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final quantity = double.parse(_quantityController.text);
      final price = double.parse(_priceController.text);
      
      await ref.read(portfolioServiceProvider).addPortfolioItem(
        portfolioId: widget.portfolio.id,
        symbol: _symbolController.text.toUpperCase(),
        name: _nameController.text.isNotEmpty 
            ? _nameController.text 
            : _symbolController.text.toUpperCase(),
        type: _selectedType,
        quantity: quantity,
        price: price,
        purchaseDate: _purchaseDate,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to portfolio successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}