# Adam style, November 2026

Direction C, "Sky": frosted cards on a flat soft-blue background. Chosen by the builder on 2026-11-02 after Chizi had no preference; closest to the ease Chizi named in Hark. Values live in `OxyApp/OxyApp/Extensions/AppTheme.swift` (`Color.adam*`, `Font.adam*`, `AdamLayout`). Changing the look means changing those values only.

## Colour

| Token | Light | Dark |
| --- | --- | --- |
| adamBackground | #7F9FC2 | #162338 |
| adamCard | white 62% | white 10% |
| adamCardEdge | white 70% | white 14% |
| adamInk | #14213A | #F3F6FB |
| adamMuted (on cards only) | #3F5578 | #B9C4D6 |
| adamAccent (the one button to press) | #14213A | #F3F6FB |
| adamOnAccent | white | #14213A |
| adamTrack (progress) | ink 15% | white 16% |

Section labels on the bare background use `adamInk`, never `adamMuted` (muted text on the sky fails contrast). One accent only. Semantic colours (`appSuccess`, `appWarning`) are reserved for real states.

## Type

System font. adamTitle 17 medium, adamBody 15, adamButton 15 medium, adamLabel 13 medium. Dynamic Type honoured; buttons wrap rather than truncate.

## Shape and space

Card radius 24, button radius 16, gutter 16, button height 44 minimum. One column. Thin 0.5pt card edge; no shadows.

## Motion

Answering an item removes its card with the existing `.appStandard` spring; under Reduce Motion it fades with no movement.
