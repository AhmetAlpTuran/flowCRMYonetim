# Bundled fonts

Static instances of two SIL Open Font License 1.1 families from the official
[google/fonts](https://github.com/google/fonts) repository, subset to Latin, Latin-1,
Latin Extended-A (all Turkish letters), general punctuation and ₺. Neither license
declares a Reserved Font Name. The licenses are in `OFL-*.txt`.

| File | Source axes |
|---|---|
| `Bricolage-{Regular,Medium,SemiBold,Bold}.ttf` | Bricolage Grotesque, opsz 14, wdth 100, wght 400/500/600/700 (UI text) |
| `BricolageDisplay-{Bold,ExtraBold}.ttf` | Bricolage Grotesque, opsz 40, wdth 100, wght 700/800 (headings) |
| `JetBrainsMono-{Regular,Medium,SemiBold}.ttf` | JetBrains Mono, wght 400/500/600 (numbers, times, status labels) |

The JetBrains Mono files are modified: the inner dot of the zero is removed so 0 never
reads as 8 at small sizes (OFL allows modified versions; there is no Reserved Font Name).
JetBrains Mono has no ₺ glyph; mono styles fall back to Bricolage for it
(`fontFamilyFallback` in `lib/ui/app_typography.dart`). To rebuild, instance the
variable fonts with `fontTools.varLib.instancer` and subset with `fontTools.subset`
using the axis values above.
