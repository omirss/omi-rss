# RSS Glassmorphism Reader

<p align="center">
  <a href="https://github.com/yourusername/rss-glassmorphism-reader/actions/workflows/ci.yml">
    <img src="https://github.com/yourusername/rss-glassmorphism-reader/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://codecov.io/gh/yourusername/rss-glassmorphism-reader">
    <img src="https://codecov.io/gh/yourusername/rss-glassmorphism-reader/branch/main/graph/badge.svg" alt="codecov">
  </a>
  <a href="https://github.com/yourusername/rss-glassmorphism-reader/releases">
    <img src="https://img.shields.io/github/v/release/yourusername/rss-glassmorphism-reader" alt="Release">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License">
  </a>
</p>

A stunning glassmorphism RSS reader that combines the functionality of FreshRSS, RSSHub, and Full-Text RSS with modern AI capabilities, market data integration, and advanced features for power users.

## ✨ Features

### 🎨 Stunning UI
- **Glassmorphism Design** - Beautiful frosted glass effects throughout the app
- **Aurora Animations** - Dynamic background animations that respond to user interaction
- **Particle Effects** - Mesmerizing particle backgrounds with customizable density
- **Smooth Transitions** - Fluid morphing animations between UI states

### 📰 Advanced Feed Management
- **Multi-format Support** - RSS 2.0, Atom, JSON Feed
- **Feed Generation** - Create RSS feeds from any website using 100+ site-specific rules
- **Batch Operations** - Manage multiple feeds simultaneously
- **Smart Categories** - Auto-categorize feeds based on content
- **Feed Statistics** - Track article frequency, read rates, and engagement

### 🤖 AI-Powered Intelligence
- **Local AI Models** - Privacy-first AI analysis without cloud dependencies
- **Sentiment Analysis** - Understand the tone of articles
- **Bias Detection** - Identify political, commercial, and sensational bias
- **Multiple Perspectives** - Get balanced viewpoints on controversial topics
- **Fact Checking** - Verify claims and detect potential misinformation
- **Smart Summaries** - AI-generated article summaries

### 🔓 Advanced Content Access
- **Paywall Bypass** - Access content from 50+ major publications
- **Full Text Extraction** - Get complete articles, not just summaries
- **Robots.txt Compliance** - Respectful crawling with rate limiting
- **Success Tracking** - Monitor bypass effectiveness

### 📊 Analytics & Insights
- **Reading Statistics** - Track your reading habits and preferences
- **Portfolio Tracking** - Follow stocks and crypto mentioned in articles
- **Real-time Alerts** - Get notified about important topics and price movements
- **Market Data Integration** - Live quotes from Polygon.io, Finnhub, and CoinGecko

### 🔄 Sync & Extensions
- **P2P Sync** - Sync between devices without cloud storage
- **End-to-end Encryption** - Your data stays private
- **Browser Extension** - Save articles from anywhere on the web
- **WebSocket Real-time** - Instant updates when connected to backend

## Getting Started

### Prerequisites

- Flutter 3.22.0 or higher
- Dart 3.0.0 or higher
- For desktop development: Visual Studio (Windows), Xcode (macOS), or build tools (Linux)

### Installation

1. Clone the repository
```bash
git clone https://github.com/yourusername/rss_glassmorphism_reader.git
cd rss_glassmorphism_reader
```

2. Install dependencies
```bash
flutter pub get
```

3. Run the app
```bash
flutter run -d windows  # or macos, linux
```

## Project Structure

```
rss_glassmorphism_reader/
├── lib/
│   ├── core/          # Core business logic
│   │   ├── models/    # Data models
│   │   ├── services/  # Services (API, parsing, etc.)
│   │   ├── parsers/   # RSS/Atom/JSON parsers
│   │   └── database/  # Database layer
│   ├── ui/            # User interface
│   │   ├── components/    # Reusable UI components
│   │   ├── animations/    # Custom animations
│   │   ├── layouts/       # Layout widgets
│   │   └── screens/       # App screens
│   ├── platform/      # Platform-specific code
│   └── server/        # Backend server code
├── assets/            # Images, animations, fonts
├── test/              # Test files
└── pubspec.yaml       # Project configuration
```

## Development

### Building for Production

#### Windows
```bash
flutter build windows --release
```

#### macOS
```bash
flutter build macos --release
```

#### Linux
```bash
flutter build linux --release
```

### Running Tests

```bash
flutter test
```

## Architecture

The app follows a clean architecture pattern with:
- **Presentation Layer**: Flutter UI with Riverpod state management
- **Domain Layer**: Business logic and use cases
- **Data Layer**: Repository pattern with local and remote data sources

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by FreshRSS, RSSHub, and Full-Text RSS
- Built with Flutter and the amazing Dart ecosystem
- Glassmorphism design inspiration from modern UI trends