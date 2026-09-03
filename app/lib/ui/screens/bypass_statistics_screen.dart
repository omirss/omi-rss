import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/models/bypass_statistics.dart';
import '../../core/services/bypass_statistics_service.dart';
import '../../providers/bypass_provider.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_dialog.dart';
import '../animations/loading_animation.dart';
import '../components/secret_menu.dart';

/// Hidden bypass statistics screen
class BypassStatisticsScreen extends ConsumerStatefulWidget {
  const BypassStatisticsScreen({super.key});

  @override
  ConsumerState<BypassStatisticsScreen> createState() => _BypassStatisticsScreenState();
}

class _BypassStatisticsScreenState extends ConsumerState<BypassStatisticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedDomain;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final statsAsync = ref.watch(bypassStatisticsProvider);
    final isEnabled = ref.watch(bypassEnabledProvider);
    
    if (!isEnabled) {
      // Show secret activation screen
      return const SecretMenuActivation();
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Extraction Statistics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Sites', icon: Icon(Icons.language)),
            Tab(text: 'Methods', icon: Icon(Icons.build)),
          ],
          indicatorColor: theme.accentColor,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: 'Bypass Settings',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmClearStats,
            tooltip: 'Clear Statistics',
          ),
        ],
      ),
      body: statsAsync.when(
        data: (stats) => TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(stats, theme),
            _buildSitesTab(stats, theme),
            _buildMethodsTab(stats, theme),
          ],
        ),
        loading: () => const Center(child: LoadingAnimation()),
        error: (error, stack) => Center(
          child: Text(
            'Failed to load statistics: $error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
  
  Widget _buildOverviewTab(OverallBypassStats stats, GlassThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Key metrics
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Sites',
                stats.totalSites.toString(),
                Icons.language,
                theme.primaryColor,
                theme,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'Active Sites',
                stats.activeSites.toString(),
                Icons.check_circle,
                Colors.green,
                theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Attempts',
                _formatNumber(stats.totalAttempts),
                Icons.play_arrow,
                Colors.blue,
                theme,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'Success Rate',
                '${(stats.overallSuccessRate * 100).toStringAsFixed(1)}%',
                Icons.trending_up,
                stats.overallSuccessRate > 0.7 ? Colors.green : Colors.orange,
                theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Success rate by category
        if (stats.successRateByCategory.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Success Rate by Category',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                ...stats.successRateByCategory.entries.map((entry) {
                  final rate = entry.value;
                  final color = rate > 0.8
                      ? Colors.green
                      : rate > 0.5
                          ? Colors.orange
                          : Colors.red;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.key.substring(0, 1).toUpperCase() + 
                              entry.key.substring(1),
                            ),
                            Text(
                              '${(rate * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: rate,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Attempts over time
        if (stats.attemptsByDay.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Activity',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _buildDailyActivityChart(stats.attemptsByDay, theme),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Hourly distribution
        if (stats.attemptsByHour.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hourly Distribution',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _buildHourlyChart(stats.attemptsByHour, theme),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildSitesTab(OverallBypassStats stats, GlassThemeData theme) {
    final allSites = [
      ...stats.topPerformingSites,
      ...stats.worstPerformingSites,
    ].toSet().toList()
      ..sort((a, b) => b.successRate.compareTo(a.successRate));
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Site search/filter
        GlassContainer(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search sites...',
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
            style: const TextStyle(color: Colors.white),
            onChanged: (value) {
              // TODO: Implement site filtering
            },
          ),
        ),
        const SizedBox(height: 16),
        
        // Site list
        ...allSites.map((site) => _buildSiteCard(site, theme)).toList(),
      ],
    );
  }
  
  Widget _buildSiteCard(SiteBypassStats site, GlassThemeData theme) {
    final color = site.successRate > 0.8
        ? Colors.green
        : site.successRate > 0.5
            ? Colors.orange
            : Colors.red;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: () => _showSiteDetails(site),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.siteName,
                        style: theme.titleSmall,
                      ),
                      Text(
                        site.domain,
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(site.successRate * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${site.totalAttempts} attempts',
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Success bar
            LinearProgressIndicator(
              value: site.successRate,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
            const SizedBox(height: 8),
            // Last attempt info
            if (site.lastAttempt != null)
              Text(
                'Last attempt: ${_formatRelativeTime(site.lastAttempt!)}',
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMethodsTab(OverallBypassStats stats, GlassThemeData theme) {
    // Aggregate method statistics across all sites
    final methodStats = <String, AggregatedMethodStats>{};
    
    for (final site in [...stats.topPerformingSites, ...stats.worstPerformingSites]) {
      for (final entry in site.methodStats.entries) {
        final method = entry.value;
        if (!methodStats.containsKey(method.method)) {
          methodStats[method.method] = AggregatedMethodStats(
            method: method.method,
            totalAttempts: 0,
            totalSuccesses: 0,
            totalDuration: Duration.zero,
            sitesUsed: 0,
          );
        }
        
        final aggregated = methodStats[method.method]!;
        methodStats[method.method] = AggregatedMethodStats(
          method: method.method,
          totalAttempts: aggregated.totalAttempts + method.attempts,
          totalSuccesses: aggregated.totalSuccesses + method.successes,
          totalDuration: aggregated.totalDuration + 
              (method.averageDuration * method.attempts),
          sitesUsed: aggregated.sitesUsed + 1,
        );
      }
    }
    
    final sortedMethods = methodStats.values.toList()
      ..sort((a, b) => b.successRate.compareTo(a.successRate));
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Method effectiveness chart
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Method Effectiveness',
                style: theme.titleMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: _buildMethodChart(sortedMethods, theme),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Method details
        ...sortedMethods.map((method) => _buildMethodCard(method, theme)).toList(),
      ],
    );
  }
  
  Widget _buildMethodCard(AggregatedMethodStats method, GlassThemeData theme) {
    final color = method.successRate > 0.8
        ? Colors.green
        : method.successRate > 0.5
            ? Colors.orange
            : Colors.red;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build, color: theme.accentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getMethodDisplayName(method.method),
                    style: theme.titleSmall,
                  ),
                ),
                Text(
                  '${(method.successRate * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${method.totalAttempts} attempts',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                Text(
                  'Used on ${method.sitesUsed} sites',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                Text(
                  'Avg: ${method.averageDuration.inMilliseconds}ms',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
    GlassThemeData theme,
  ) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDailyActivityChart(Map<DateTime, int> data, GlassThemeData theme) {
    final sortedEntries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    if (sortedEntries.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }
    
    final spots = sortedEntries.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value.toDouble());
    }).toList();
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (sortedEntries.length / 5).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= sortedEntries.length) return const SizedBox();
                final date = sortedEntries[value.toInt()].key;
                return Text(
                  '${date.month}/${date.day}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: theme.accentColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: theme.accentColor.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHourlyChart(Map<String, int> data, GlassThemeData theme) {
    final spots = <FlSpot>[];
    for (int hour = 0; hour < 24; hour++) {
      final hourStr = hour.toString().padLeft(2, '0');
      spots.add(FlSpot(hour.toDouble(), (data[hourStr] ?? 0).toDouble()));
    }
    
    return BarChart(
      BarChartData(
        barGroups: List.generate(24, (hour) {
          final hourStr = hour.toString().padLeft(2, '0');
          final value = data[hourStr] ?? 0;
          
          return BarChartGroupData(
            x: hour,
            barRods: [
              BarChartRodData(
                toY: value.toDouble(),
                color: theme.primaryColor,
                width: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
  
  Widget _buildMethodChart(List<AggregatedMethodStats> methods, GlassThemeData theme) {
    return BarChart(
      BarChartData(
        barGroups: methods.asMap().entries.map((entry) {
          final index = entry.key;
          final method = entry.value;
          
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: method.successRate * 100,
                color: method.successRate > 0.8
                    ? Colors.green
                    : method.successRate > 0.5
                        ? Colors.orange
                        : Colors.red,
                width: 30,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= methods.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _getMethodDisplayName(methods[value.toInt()].method),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}%',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        maxY: 100,
      ),
    );
  }
  
  void _showSiteDetails(SiteBypassStats site) {
    showGlassDialog(
      context: context,
      title: Text(site.siteName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('Domain', site.domain),
          _buildDetailRow('Success Rate', '${(site.successRate * 100).toStringAsFixed(1)}%'),
          _buildDetailRow('Total Attempts', site.totalAttempts.toString()),
          _buildDetailRow('Successful', site.successfulAttempts.toString()),
          _buildDetailRow('Failed', site.failedAttempts.toString()),
          if (site.lastSuccess != null)
            _buildDetailRow('Last Success', _formatRelativeTime(site.lastSuccess!)),
          _buildDetailRow('Avg Duration', '${site.averageDuration.inMilliseconds}ms'),
          const SizedBox(height: 16),
          const Text(
            'Method Performance:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...site.methodStats.values.map((method) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_getMethodDisplayName(method.method)),
                Text(
                  '${(method.successRate * 100).toStringAsFixed(0)}% (${method.attempts} attempts)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          )),
          if (site.commonErrors.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Common Errors:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...site.commonErrors.map((error) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $error',
                style: TextStyle(
                  color: Colors.red.shade300,
                  fontSize: 12,
                ),
              ),
            )),
          ],
        ],
      ),
      actions: [
        GlassButton(
          text: 'Clear Site Stats',
          onPressed: () {
            Navigator.of(context).pop();
            _clearSiteStats(site.domain);
          },
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
  
  void _showSettingsDialog() {
    final config = ref.read(bypassConfigProvider);
    
    showGlassDialog(
      context: context,
      title: const Text('Bypass Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Enable Bypass'),
            value: config.enabled,
            onChanged: (value) {
              ref.read(bypassConfigProvider.notifier).updateConfig(
                config.copyWith(enabled: value),
              );
            },
          ),
          SwitchListTile(
            title: const Text('Auto Retry'),
            subtitle: Text('Max retries: ${config.maxRetries}'),
            value: config.autoRetry,
            onChanged: (value) {
              ref.read(bypassConfigProvider.notifier).updateConfig(
                config.copyWith(autoRetry: value),
              );
            },
          ),
          SwitchListTile(
            title: const Text('Collect Statistics'),
            subtitle: const Text('Track success rates'),
            value: config.collectStats,
            onChanged: (value) {
              ref.read(bypassConfigProvider.notifier).updateConfig(
                config.copyWith(collectStats: value),
              );
            },
          ),
          SwitchListTile(
            title: const Text('Anonymize Data'),
            subtitle: const Text('Remove identifying info'),
            value: config.anonymizeData,
            onChanged: (value) {
              ref.read(bypassConfigProvider.notifier).updateConfig(
                config.copyWith(anonymizeData: value),
              );
            },
          ),
        ],
      ),
      actions: [
        GlassButton(
          text: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
  
  void _confirmClearStats() async {
    final confirmed = await showGlassConfirmDialog(
      context: context,
      title: 'Clear Statistics',
      message: 'Are you sure you want to clear all bypass statistics? This action cannot be undone.',
      confirmText: 'Clear',
      destructive: true,
    );
    
    if (confirmed == true) {
      await ref.read(bypassStatisticsServiceProvider).clearStats();
      ref.invalidate(bypassStatisticsProvider);
    }
  }
  
  void _clearSiteStats(String domain) async {
    await ref.read(bypassStatisticsServiceProvider).clearSiteStats(domain);
    ref.invalidate(bypassStatisticsProvider);
  }
  
  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
  
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
  
  String _getMethodDisplayName(String method) {
    final displayNames = {
      'googlebot': 'Googlebot UA',
      'amp': 'AMP Version',
      'archive': 'Archive Service',
      'javascript': 'JS Override',
      'cookie': 'Cookie Injection',
      'referrer': 'Referrer Spoofing',
      'dom': 'DOM Manipulation',
      'pdf_redirect': 'PDF Direct',
      'institutional_proxy': 'Institutional',
    };
    
    return displayNames[method] ?? method;
  }
}

/// Aggregated method statistics
class AggregatedMethodStats {
  final String method;
  final int totalAttempts;
  final int totalSuccesses;
  final Duration totalDuration;
  final int sitesUsed;
  
  AggregatedMethodStats({
    required this.method,
    required this.totalAttempts,
    required this.totalSuccesses,
    required this.totalDuration,
    required this.sitesUsed,
  });
  
  double get successRate => totalAttempts > 0 ? totalSuccesses / totalAttempts : 0.0;
  Duration get averageDuration => totalAttempts > 0 
      ? Duration(microseconds: totalDuration.inMicroseconds ~/ totalAttempts)
      : Duration.zero;
}