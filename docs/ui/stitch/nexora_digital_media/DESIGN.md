---
name: Nexora Digital Media
colors:
  surface: '#f9f9ff'
  surface-dim: '#d8d9e3'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3fd'
  surface-container: '#ecedf7'
  surface-container-high: '#e6e8f2'
  surface-container-highest: '#e0e2ec'
  on-surface: '#191c23'
  on-surface-variant: '#414754'
  inverse-surface: '#2d3038'
  inverse-on-surface: '#eff0fa'
  outline: '#727785'
  outline-variant: '#c1c6d6'
  surface-tint: '#005bc0'
  primary: '#005bbf'
  on-primary: '#ffffff'
  primary-container: '#1a73e8'
  on-primary-container: '#ffffff'
  inverse-primary: '#adc7ff'
  secondary: '#006876'
  on-secondary: '#ffffff'
  secondary-container: '#58e6ff'
  on-secondary-container: '#006573'
  tertiary: '#006d2b'
  on-tertiary: '#ffffff'
  tertiary-container: '#24883f'
  on-tertiary-container: '#000601'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d8e2ff'
  primary-fixed-dim: '#adc7ff'
  on-primary-fixed: '#001a41'
  on-primary-fixed-variant: '#004493'
  secondary-fixed: '#a1efff'
  secondary-fixed-dim: '#44d8f1'
  on-secondary-fixed: '#001f25'
  on-secondary-fixed-variant: '#004e59'
  tertiary-fixed: '#96f8a1'
  tertiary-fixed-dim: '#7adb87'
  on-tertiary-fixed: '#002108'
  on-tertiary-fixed-variant: '#00531f'
  background: '#f9f9ff'
  on-background: '#191c23'
  surface-variant: '#e0e2ec'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
  title-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  gutter: 16px
  margin-mobile: 20px
  margin-desktop: 40px
  touch-target: 48px
---

## Brand & Style

The design system is engineered for a premium, high-velocity media utility that balances technical power with a polished consumer aesthetic. The personality is efficient, reliable, and sophisticated, avoiding the cluttered "downloader" tropes in favor of a clean, Material 3-inspired interface.

The design style is **Corporate Modern with a Tactile Twist**. It leverages the structural logic of Material 3 but enhances it with larger radius geometry and soft, ambient shadows to feel more like a premium lifestyle app. The interface prioritizes one-handed mobile ergonomics, featuring generous touch targets and a clear visual hierarchy that guides the user through the download lifecycle—from URL input to media management—without friction.

## Colors

The palette is centered on a vibrant "Electric Blue" primary that signals trust and action. A "Cyan" accent is used sparingly to highlight progress indicators and active states, providing a modern, tech-forward energy. 

- **Primary (#1A73E8):** Used for main actions, active navigation states, and primary buttons.
- **Secondary (#00BCD4):** Reserved for accent details, progress bars, and high-energy micro-interactions.
- **Neutral/Surface:** A layered approach using a very light gray background to allow pure white cards to "pop" with clear elevation.
- **Semantic:** Standardized Red and Green for error and success states, maintaining high legibility against the light background.

## Typography

The typography system utilizes **Inter** to achieve a clean, systematic look that remains highly readable across various screen densities. 

- **Headlines:** Large and bold to provide a strong anchor for page layouts. On mobile, headlines scale down slightly to ensure they don't break awkwardly while maintaining their visual weight.
- **Body Text:** Standardized on a 16px base for optimal readability in media descriptions and file lists.
- **Labels:** Medium-weight (500) and slightly tracked out for use in interactive chips and button text, ensuring they are distinct from body content.

## Layout & Spacing

This design system uses a **Fluid Grid** approach with an emphasis on "Comfortable Whitespace." 

- **Mobile:** A 4-column grid with 20px outside margins. All primary interactive elements (buttons, inputs) must adhere to a minimum height of 48px to support one-handed use.
- **Desktop:** A 12-column grid with 40px margins, maxing out at 1440px width. 
- **Rhythm:** An 8px base unit governs all padding and margins. Vertical rhythm is relaxed, ensuring media cards and list items have enough "breathing room" to prevent the UI from feeling like a utility tool.

## Elevation & Depth

Hierarchy is established through **Tonal Layers** and **Ambient Shadows**. 

- **Level 0 (Background):** #F8F9FA.
- **Level 1 (Cards/Surfaces):** Pure white (#FFFFFF) with a very soft, diffused shadow (0px 4px 20px rgba(0, 0, 0, 0.04)).
- **Level 2 (Active/Hover):** Increased shadow depth (0px 8px 30px rgba(0, 0, 0, 0.08)) to indicate interactivity.
- **Transitions:** Use smooth, 200ms ease-out transitions for elevation changes. Avoid harsh borders; use subtle 1px inner strokes in #EDF0F2 for definition on white surfaces if needed.

## Shapes

The shape language is "Hyper-Rounded" to soften the technical nature of a media downloader.

- **Standard Containers:** 16px corner radius (e.g., small cards, input fields).
- **Large Containers:** 24px corner radius (e.g., main action sheets, featured media cards).
- **Interactive Elements:** Buttons use a fully rounded (pill) shape or a 12px radius depending on context.
- **Icons:** Always use Material Symbols Rounded to maintain harmony with the container geometry.

## Components

- **Primary Action Button:** Pill-shaped, Primary Blue background, white Inter Medium text. Height: 56px for mobile prominence.
- **Media Cards:** 24px radius, pure white background, subtle ambient shadow. Images/Thumbnails within the card should have a 16px top-radius.
- **Input Fields:** 16px radius, #F1F3F4 background (light gray), no border until focused. On focus, apply a 2px Primary Blue border.
- **Progress Chips:** 12px radius, light cyan background with Primary Blue text, used to show download status (e.g., "720p", "Downloading").
- **Bottom Sheets:** For mobile, use a 32px top-corner radius. Include a subtle drag handle.
- **Lists:** High-density lists should have 16px vertical padding per item with a subtle 1px separator that doesn't reach the edge of the screen.