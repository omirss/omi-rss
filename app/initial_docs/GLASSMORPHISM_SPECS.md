# Glassmorphism Design Specifications

## Core Principles

1. **Transparency**: Semi-transparent surfaces with backdrop blur
2. **Depth**: Multiple layers creating spatial hierarchy
3. **Light**: Subtle gradients and highlights suggesting light sources
4. **Motion**: Smooth animations reinforcing material properties
5. **Clarity**: High contrast text ensuring readability

## Visual Properties

### Glass Effect Parameters
```dart
const glassEffect = {
  'blur': 20.0,           // Backdrop blur intensity
  'opacity': 0.15,        // Surface opacity (0.1-0.3)
  'borderOpacity': 0.18,  // Border visibility
  'borderWidth': 1.5,     // Consistent border width
  'shadowBlur': 32.0,     // Shadow softness
  'shadowOpacity': 0.37,  // Shadow transparency
};
```

### Color Palette
```dart
// Primary Glass Colors
const darkBlue = Color(0xFF0B1929);    // Deep navy background
const purple = Color(0xFF1F268C);      // Royal purple accent
const teal = Color(0xFF0EA5E9);        // Bright teal highlight
const pink = Color(0xFFEC4899);        // Vivid pink accent

// Glass Gradients
const blueGradient = [Color(0x26146FB1), Color(0x0D146FB1)];
const purpleGradient = [Color(0x265936B5), Color(0x0D5936B5)];
const tealGradient = [Color(0x260EA5E9), Color(0x0D0EA5E9)];
const pinkGradient = [Color(0x26EC4899), Color(0x0DEC4899)];

// Neutral Glass
const whiteGlass = [Color(0x26FFFFFF), Color(0x0DFFFFFF)];
const blackGlass = [Color(0x26000000), Color(0x0D000000)];
```

## Component Specifications

### GlassContainer
- **Base Properties**:
  - Blur: 20px backdrop filter
  - Opacity: 0.15 fill
  - Border: 1.5px white at 0.18 opacity
  - Shadow: 32px blur, purple tint
  - Corners: 16px radius (default)

- **Hover State**:
  - Scale: 1.02x
  - Elevation: +4px
  - Border opacity: 0.25
  - Transition: 300ms ease

- **Active State**:
  - Scale: 0.98x
  - Shadow: Reduced by 50%
  - Background: +0.05 opacity

### GlassCard
- **Elevation Levels**:
  - Level 1: 8px shadow offset, 24px blur
  - Level 2: 16px shadow offset, 32px blur
  - Level 3: 24px shadow offset, 48px blur
  - Level 4: 32px shadow offset, 64px blur

- **Swipe Actions**:
  - Dismiss threshold: 0.3 screen width
  - Rubber band effect beyond threshold
  - Fade out on dismiss
  - Spring animation on cancel

### GlassButton
- **Variants**:
  1. **Elevated**: Full glass effect with shadow
  2. **Outlined**: Border only, no fill
  3. **Text**: No background, hover reveals glass
  4. **Icon**: Circular with centered icon
  5. **FAB**: Floating with strong elevation

- **States**:
  - Default: Base glass effect
  - Hover: +2px elevation, glow effect
  - Pressed: -2px elevation, darken
  - Disabled: 0.5 opacity, no hover
  - Loading: Shimmer animation

### GlassTextField
- **Structure**:
  - Container: Glass background
  - Label: Floats on focus/content
  - Border: Animated color on focus
  - Helper: Below field, smaller text

- **Focus Animation**:
  - Border: Teal color sweep
  - Label: Scale 0.75x, move up
  - Background: +0.05 opacity
  - Duration: 200ms

### Glass Dialogs
- **Background**: 0.8 opacity black overlay
- **Dialog**: Strong glass effect, centered
- **Animation**: Scale + fade in
- **Actions**: Glass buttons in footer

## Animation Specifications

### Hover Effects
```dart
// Magnetic hover - cursor attraction
const magneticHover = {
  'range': 50.0,          // Pixel range
  'strength': 0.3,        // Movement multiplier
  'returnSpeed': 0.1,     // Spring back speed
};

// Ripple effect on click
const rippleEffect = {
  'duration': 600,        // Milliseconds
  'opacity': 0.3,         // Ripple opacity
  'scale': 2.0,          // Final size multiplier
};
```

### Particle System
- **Count**: 50+ particles
- **Size**: 4-12px random
- **Speed**: 0.1-0.5px per frame
- **Opacity**: 0.1-0.3 random
- **Blur**: 20-40px random
- **Color**: Theme gradient colors
- **Movement**: Sine wave paths
- **Mouse**: Repel within 100px

### Page Transitions
1. **Slide Glass**: Next page slides over with glass trail
2. **Morph**: Elements transform between pages
3. **Shatter**: Current page breaks into glass shards
4. **Liquid**: Fluid transition between states

## Responsive Behavior

### Breakpoints
- Mobile: < 600px
- Tablet: 600-1024px
- Desktop: > 1024px

### Adaptive Properties
- **Mobile**: Reduced blur (15px) for performance
- **Tablet**: Standard effects
- **Desktop**: Enhanced with extra particles

### Performance Optimizations
- Use `will-change` for animated properties
- Reduce blur on scroll
- Disable particles on low-end devices
- Cache rendered glass surfaces
- Use GPU-accelerated filters

## Accessibility

### Contrast Requirements
- Text on glass: Minimum 4.5:1 ratio
- Use solid backgrounds for critical text
- Provide high contrast mode option
- Ensure focus indicators are visible

### Motion Preferences
- Respect `prefers-reduced-motion`
- Provide toggle for animations
- Keep essential animations subtle
- Avoid parallax on mobile

## Implementation Guidelines

### Do's
- ✅ Layer multiple glass surfaces for depth
- ✅ Use consistent blur values across components
- ✅ Animate properties smoothly
- ✅ Ensure text remains readable
- ✅ Test on various backgrounds
- ✅ Optimize for performance

### Don'ts
- ❌ Over-blur (max 30px)
- ❌ Stack too many layers (max 4)
- ❌ Use pure white/black
- ❌ Forget border highlights
- ❌ Animate blur values directly
- ❌ Ignore performance impact

## Platform Considerations

### iOS
- Use `UIVisualEffectView` for native blur
- Respect safe areas for glass elements
- Match iOS glass semantics

### Android
- Use `RenderEffect` on Android 12+
- Fallback to custom blur on older versions
- Follow Material You principles

### Web
- Progressive enhancement approach
- Fallback for browsers without backdrop-filter
- Optimize for Chromium-based browsers

### Desktop
- Utilize native window effects where possible
- Higher quality blur for larger screens
- Extended hover states for mouse input