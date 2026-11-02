# Adam style, November 2026

Black, white and the system. No brand colour. Values live in `OxyApp/OxyApp/Extensions/AppTheme.swift` (`Color.adam*`, `Font.adam*`, `AdamLayout`).

## Colour

Every token is an iOS system colour, so light and dark follow the phone.

| Token | System colour |
| --- | --- |
| adamBackground | systemBackground |
| adamCard | secondarySystemBackground |
| adamCardEdge | separator at 50% |
| adamInk | label |
| adamMuted | secondaryLabel |
| adamAccent (the one button to press) | label |
| adamOnAccent | systemBackground |
| adamTrack (progress) | systemFill |

Semantic colours (`appSuccess`, `appWarning`) are reserved for real states.

## Type

System font. adamTitle 17 medium, adamBody 15, adamButton 15 medium, adamLabel 13 medium. Dynamic Type honoured; buttons wrap rather than truncate.

## Shape and space

Card radius 24, button radius 16, gutter 16, button height 44 minimum. One column. Thin card edge; no shadows.

## Motion

Answering an item removes its card with the existing `.appStandard` spring; under Reduce Motion there is no movement.
