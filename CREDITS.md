# Credits

## Photography

The pause's backdrop changes with the time of day (`DayPeriod` in
`Shift/Enforcement/PauseBackdrop.swift`). All five photos are free under the
[Unsplash License](https://unsplash.com/license): free for commercial use, no permission or
attribution required. Credited here anyway.

| Asset | Hours | Photo | Photographer | Source |
|---|---|---|---|---|
| `BackdropSunrise` | 05:00–09:00 | Misty meadow at sunrise, Maple Ridge, BC | James Wheeler | <https://unsplash.com/photos/3K4dzt7lBNM> |
| `BackdropMorning` | 09:00–13:00 | Green hills under a blue sky, Livermore, CA | Spencer DeMera | <https://unsplash.com/photos/mnQLdWwZ_wQ> |
| `BackdropAfternoon` | 13:00–17:00 | Acacia trees on savanna, Masai Mara, Kenya | David Clode | <https://unsplash.com/photos/92MgFhlWD-8> |
| `BackdropSunset` | 17:00–20:30 | Green field at sunset, Syracuse, NY | Tom Dillon | <https://unsplash.com/photos/rnU84NyFLJM> |
| `BackdropNight` | 20:30–05:00 | Milky Way over Schafberg, Austria | Sebastian Knoll | <https://unsplash.com/photos/2YjnI6oSGnk> |

The Unsplash License forbids two things we are not doing: selling unaltered copies of the
photo, and using Unsplash photos to build a competing stock-photo service. Note also that
the separate Unsplash **API** terms *do* mandate attribution — these images were downloaded
directly rather than fetched through the API, so those terms don't apply, but don't wire
up the API later without revisiting this.

Everything else in the app — the icon, the nudge character — is generated or drawn in
code. See `Tools/make-icon.swift` and `Shift/UI/NudgeCharacterView.swift`.
