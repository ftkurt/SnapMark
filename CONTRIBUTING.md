# Contributing

Thanks for helping improve SnapMark.

1. Fork the repository and create a descriptive feature branch.
2. Keep the app dependency-free unless a dependency provides substantial,
   reviewed value.
3. Build with `./build-app.sh`.
4. Test region capture, cancellation, annotation, clipboard output, and mixed
   display layouts when the change touches capture behavior.
5. Open a pull request describing the behavior change and validation performed.

## Safety invariant

Changes to the capture overlay must preserve all independent cancellation
paths: `Esc`, `⌘.`, right-click, the visible Cancel button, menu-bar access,
`⌘Q`, and the automatic timeout. A capture overlay must never be able to trap
the desktop.
