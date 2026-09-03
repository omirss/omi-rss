import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../discovery_service.dart';

class CustomFeedGenerator extends StatefulWidget {
  final Function(List<FeedSuggestion>) onFeedGenerated;

  const CustomFeedGenerator({
    super.key,
    required this.onFeedGenerated,
  });

  @override
  State<CustomFeedGenerator> createState() => _CustomFeedGeneratorState();
}

class _CustomFeedGeneratorState extends State<CustomFeedGenerator> {
  final TextEditingController _promptController = TextEditingController();
  bool _isGenerating = false;
  String? _error;

  final List<String> _examplePrompts = [
    'Tech news about AI and machine learning',
    'Environmental science and climate change',
    'Startup news and entrepreneurship',
    'Mobile app development tutorials',
    'Healthy cooking and nutrition',
    'Space exploration and astronomy',
    'Personal finance and investing',
    'Web development best practices',
  ];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generateFeed() async {
    if (_promptController.text.trim().isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final discoveryService = context.read<DiscoveryService>();
      final suggestions = await discoveryService.generateCustomFeed(
        _promptController.text.trim(),
      );

      if (suggestions.isNotEmpty) {
        widget.onFeedGenerated(suggestions);
        _promptController.clear();
      } else {
        setState(() {
          _error = 'No feeds found matching your description';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to generate feeds: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI-Powered Feed Discovery',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Describe what kind of content you\'re interested in, and we\'ll find the perfect feeds for you.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'E.g., "I want to read about sustainable technology and renewable energy innovations"',
              labelText: 'Describe your interests',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
            enabled: !_isGenerating,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _isGenerating ? null : _generateFeed,
              child: _isGenerating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Generate Feed Suggestions'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Try these examples:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _examplePrompts.map((prompt) {
              return ActionChip(
                label: Text(prompt),
                onPressed: _isGenerating
                    ? null
                    : () {
                        _promptController.text = prompt;
                      },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tips for better results',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTip('Be specific about topics you\'re interested in'),
                  _buildTip('Mention preferred content types (news, tutorials, analysis)'),
                  _buildTip('Include any specific publications or authors you like'),
                  _buildTip('Specify language preferences if not English'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}