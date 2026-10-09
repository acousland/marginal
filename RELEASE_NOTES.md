# Marginal 1.2.4

- Fix a text-view resizing loop that could crash while zooming on macOS 27, including trackpad pinch gestures.
- Keep text reflow out of synchronous scroll-view bounds notifications and avoid unnecessary table layout invalidation.
- Zoom, word wrap, and saved Markdown retain their existing behavior.
