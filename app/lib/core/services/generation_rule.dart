import 'package:yaml/yaml.dart';

/// Generation rule for a website
class GenerationRule {
  final String site;
  final String name;
  final List<RulePattern> patterns;
  final RuleSelectors selectors;
  final List<RuleTransform> transforms;
  final bool javascriptRequired;
  final int rateLimit;
  final String? userAgent;
  final Map<String, dynamic>? customHeaders;
  final String? encoding;
  
  GenerationRule({
    required this.site,
    required this.name,
    required this.patterns,
    required this.selectors,
    this.transforms = const [],
    this.javascriptRequired = false,
    this.rateLimit = 0,
    this.userAgent,
    this.customHeaders,
    this.encoding,
  });
  
  /// Create from YAML
  factory GenerationRule.fromYaml(Map yaml) {
    // Parse patterns
    final patterns = <RulePattern>[];
    if (yaml['patterns'] != null) {
      for (final pattern in yaml['patterns']) {
        patterns.add(RulePattern(
          pattern: pattern['pattern'] as String,
          example: pattern['example'] as String?,
        ));
      }
    }
    
    // Parse selectors
    final selectorsMap = yaml['selectors'] as Map;
    final selectors = RuleSelectors(
      feedTitle: RuleSelector.fromYaml(selectorsMap['feed_title']),
      feedDescription: selectorsMap['feed_description'] != null 
        ? RuleSelector.fromYaml(selectorsMap['feed_description'])
        : RuleSelector(css: '', attribute: 'text'),
      items: RuleSelector.fromYaml(selectorsMap['items']),
      itemTitle: RuleSelector.fromYaml(selectorsMap['item_title']),
      itemLink: RuleSelector.fromYaml(selectorsMap['item_link']),
      itemContent: selectorsMap['item_content'] != null
        ? RuleSelector.fromYaml(selectorsMap['item_content'])
        : RuleSelector(css: '', attribute: 'text'),
      itemDate: selectorsMap['item_date'] != null
        ? RuleSelector.fromYaml(selectorsMap['item_date'])
        : RuleSelector(css: '', attribute: 'text'),
      itemAuthor: selectorsMap['item_author'] != null
        ? RuleSelector.fromYaml(selectorsMap['item_author'])
        : RuleSelector(css: '', attribute: 'text'),
      itemImage: selectorsMap['item_image'] != null
        ? RuleSelector.fromYaml(selectorsMap['item_image'])
        : null,
      itemCategories: selectorsMap['item_categories'] != null
        ? RuleSelector.fromYaml(selectorsMap['item_categories'])
        : null,
    );
    
    // Parse transforms
    final transforms = <RuleTransform>[];
    if (yaml['transforms'] != null) {
      for (final transform in yaml['transforms']) {
        transforms.add(RuleTransform.fromYaml(transform));
      }
    }
    
    return GenerationRule(
      site: yaml['site'] as String,
      name: yaml['name'] as String,
      patterns: patterns,
      selectors: selectors,
      transforms: transforms,
      javascriptRequired: yaml['javascript_required'] ?? false,
      rateLimit: yaml['rate_limit'] ?? 0,
      userAgent: yaml['user_agent'] as String?,
      customHeaders: yaml['custom_headers'] as Map<String, dynamic>?,
      encoding: yaml['encoding'] as String?,
    );
  }
}

/// URL pattern for matching
class RulePattern {
  final String pattern;
  final String? example;
  
  RulePattern({
    required this.pattern,
    this.example,
  });
}

/// Selectors for extracting data
class RuleSelectors {
  final RuleSelector feedTitle;
  final RuleSelector feedDescription;
  final RuleSelector items;
  final RuleSelector itemTitle;
  final RuleSelector itemLink;
  final RuleSelector itemContent;
  final RuleSelector itemDate;
  final RuleSelector itemAuthor;
  final RuleSelector? itemImage;
  final RuleSelector? itemCategories;
  
  RuleSelectors({
    required this.feedTitle,
    required this.feedDescription,
    required this.items,
    required this.itemTitle,
    required this.itemLink,
    required this.itemContent,
    required this.itemDate,
    required this.itemAuthor,
    this.itemImage,
    this.itemCategories,
  });
}

/// Individual selector
class RuleSelector {
  final String css;
  final String attribute;
  final String? regex;
  final int? index;
  
  RuleSelector({
    required this.css,
    required this.attribute,
    this.regex,
    this.index,
  });
  
  /// Create from YAML
  factory RuleSelector.fromYaml(dynamic yaml) {
    if (yaml is String) {
      return RuleSelector(css: yaml, attribute: 'text');
    } else if (yaml is Map) {
      return RuleSelector(
        css: yaml['css'] as String,
        attribute: yaml['attr'] ?? 'text',
        regex: yaml['regex'] as String?,
        index: yaml['index'] as int?,
      );
    }
    throw ArgumentError('Invalid selector format');
  }
}

/// Transform to apply to extracted data
class RuleTransform {
  final String action;
  final String? selector;
  final String? base;
  final String? find;
  final String? replace;
  final Map<String, dynamic>? params;
  
  RuleTransform({
    required this.action,
    this.selector,
    this.base,
    this.find,
    this.replace,
    this.params,
  });
  
  /// Create from YAML
  factory RuleTransform.fromYaml(Map yaml) {
    return RuleTransform(
      action: yaml['action'] as String,
      selector: yaml['selector'] as String?,
      base: yaml['base'] as String?,
      find: yaml['find'] as String?,
      replace: yaml['replace'] as String?,
      params: yaml['params'] as Map<String, dynamic>?,
    );
  }
}