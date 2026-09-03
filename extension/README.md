# Omi RSS Browser Extension

A beautiful browser extension for the Omi RSS Reader featuring stunning glassmorphism UI design.

## Features

### 🎨 Beautiful Glassmorphism Design
- Glass-like transparent backgrounds with blur effects
- Smooth gradients and particle animations
- Consistent design language across all views
- Dark theme optimized for readability

### 🚀 Quick Actions
- **Pop Out Window** - Open extension in a standalone window
- **Full Web Version** - Access the complete web application
- **Open Sidebar** - Use Chrome's side panel for persistent access

### 📰 Core Functionality
- Save articles from any webpage
- Detect RSS feeds on current page
- Quick access to your feed subscriptions
- Offline reading mode
- Real-time sync with server

### 🌐 Cross-Browser Support
- **Chrome/Edge**: Full support including side panel API
- **Firefox**: Complete functionality with popup fallback
- **Safari**: Webkit prefixes for compatibility

## Installation

### Chrome/Edge
1. Open `chrome://extensions` (or `edge://extensions`)
2. Enable "Developer mode" in the top right
3. Click "Load unpacked"
4. Select the `browser_extension` folder
5. Pin the Omi RSS icon to your toolbar

### Firefox
1. Open `about:debugging`
2. Click "This Firefox"
3. Click "Load Temporary Add-on"
4. Select any file in the `browser_extension` folder
5. The extension will appear in your toolbar

### Building for Distribution
```bash
# Windows
build.bat

# Mac/Linux
chmod +x build.sh
./build.sh
```

This creates:
- `build/omi-rss-chrome.zip` - For Chrome Web Store
- `build/omi-rss-firefox.zip` - For Firefox Add-ons

## UI Components

### Glassmorphism Elements
- **Glass Cards**: Semi-transparent cards with backdrop blur
- **Glass Buttons**: Multiple variants (primary, secondary, ghost)
- **Glass Inputs**: Styled form inputs with focus states
- **Glass Modals**: Beautiful overlay dialogs
- **Glass Navigation**: Sidebar and tab navigation

### Animation Effects
- Floating particles in background
- Smooth hover transitions
- Loading spinners with glow
- Button press feedback
- Card hover elevation

## Development

### File Structure
```
browser_extension/
├── manifest.json          # Chrome manifest
├── manifest_firefox.json  # Firefox manifest
├── popup.html            # Main popup interface
├── sidepanel.html        # Chrome side panel
├── css/
│   ├── glassmorphism.css # Shared glass components
│   ├── popup.css         # Popup specific styles
│   └── sidepanel.css     # Side panel styles
├── js/
│   ├── popup.js          # Popup functionality
│   ├── sidepanel.js      # Side panel logic
│   └── browser-compat.js # Cross-browser compatibility
└── icons/               # Extension icons
```

### Testing
1. Open `test-extension.html` in a browser to preview the UI
2. Use `generate-icons.html` to create new icon sizes
3. Test in both Chrome and Firefox for compatibility

### Customization
The glassmorphism design system uses CSS custom properties for easy theming:

```css
:root {
  --primary-gradient: linear-gradient(135deg, #FF6B6B 0%, #FFE66D 100%);
  --glass-bg: rgba(255, 255, 255, 0.1);
  --glass-border: rgba(255, 255, 255, 0.2);
  --blur-md: 20px;
}
```

## Browser Compatibility

### Chrome/Edge (Manifest V3)
- ✅ Side panel API
- ✅ Service workers
- ✅ Declarative net request
- ✅ All glassmorphism effects

### Firefox (Manifest V2/V3)
- ✅ Browser action
- ✅ Background scripts
- ✅ WebRequest API
- ✅ Glassmorphism with -moz prefixes

### Safari
- ⚠️ Requires Safari Web Extension conversion
- ✅ Webkit backdrop-filter support
- ✅ All visual effects supported

## Keyboard Shortcuts

- `Alt+R` - Open popup (customizable)
- `Escape` - Close reader view
- `S` - Save current article
- `R` - Refresh feeds

## Privacy

The extension requires minimal permissions:
- `activeTab` - To detect feeds on current page
- `storage` - To save settings and offline data
- `Host permission` - To connect to your RSS server

## Support

- Report issues on [GitHub](https://github.com/omi-rss/extension)
- Check the [FAQ](https://docs.omi-rss.com/extension)
- Join our [Discord](https://discord.gg/omi-rss)

## License

MIT License - See LICENSE file for details