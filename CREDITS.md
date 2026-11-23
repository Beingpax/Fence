# Credits

## Pause wallpapers

The wallpapers in `Shift/Resources/Wallpapers` were generated for Shift. Acacia Plain,
Red Dune and Snowy Ridge used provided landscape references. Green Hills was generated
from a written brief. Each landscape has five matching lighting variants. The pause
rotates landscapes by local calendar day and chooses the lighting by local time.

Everything else in the app — the icon, the nudge character — is generated or drawn in
code. See `Tools/make-icon.swift` and `Shift/UI/NudgeCharacterView.swift`.

## Adult domain catalog

The Adult sites category in WebsiteCategories.json adapts the Bon-Appetit/porn-domains blocklist and allowlist. That category is distributed under the same Creative Commons Attribution-ShareAlike 4.0 license. The upstream snapshot and rebuild instructions are in Tools/build-adult-catalog.py. [Source snapshot](https://github.com/Bon-Appetit/porn-domains/tree/e49b7131ba1e407f240dffc055bb51dfa824cd7a) · [License](https://creativecommons.org/licenses/by-sa/4.0/)

The catalog records which blocked hosts are also present in Sinfonietta’s pornography hosts file for the Adult sites filter. The generator uses the Public Suffix List to identify shared suffixes. [Sinfonietta source](https://github.com/Sinfonietta/hostfiles/tree/4f7229bea95b8b0116fd3022359b3828ccd022c0) · [Public Suffix List snapshot](https://github.com/publicsuffix/list/blob/763a4c200052f4cbc42fc123d2a80ff9437103c7/public_suffix_list.dat)
