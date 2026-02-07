# Ping Warden 2.1.1

## Dashboard and settings polish

- Refined dashboard card hierarchy and spacing so metrics and controls read more clearly.
- Reworked the `Connection Settings` card into aligned setting rows for cleaner scanability.
- Fixed `HOW IT WORKS` width behavior in General settings so it fills the panel consistently.

## Timeframe behavior and chart clarity

- Added a `1 min` timeframe option to ping history.
- Timeframe changes now clearly "zoom" the chart window to the selected recent duration.
- Added explicit zoom context text in the chart header and improved short-window x-axis labeling.
- Timeframe switching remains non-destructive and does not clear collected ping history.

## Menu bar metrics option

- Added a new option to show live metrics in the menu dropdown:
  - Current ping
  - AWDL intervention count
- Added a matching toggle in `General -> App -> Menu Dropdown Metrics`.
