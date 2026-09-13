# Fonts

**Lato** by Łukasz Dziedzic, licensed under the **SIL Open Font License 1.1**.

The OFL permits bundling and redistribution inside a product, including
commercially, provided the font is not sold on its own and **the licence and
the copyright notice travel with it** (clause 2). Both are satisfied:

- `OFL.txt` holds the full SIL Open Font License 1.1. Its body is the official
  text byte for byte; only the template's `<Copyright Holder>` placeholders were
  filled in, with the notice read out of the font's own name table rather than
  written from memory.
- Both export presets name it in `include_filter`. They have to: the presets
  export `all_resources`, and a plain `.txt` is not a resource Godot imports, so
  the licence would otherwise sit here in the repository and never reach anyone
  who downloaded the game — which is the same as not having it.

`tools/licence_check.gd` verifies all of that, including that the built packs
themselves contain the text. It is not in the routine suite, because it depends
on there being a build to look at. Run it before publishing:

    Godot_console.exe --headless --path . --script res://tools/licence_check.gd

Four weights are shipped. They are the whole type system; if you find yourself
wanting a fifth, the layout is probably doing the work the hierarchy should:

| Weight   | Used for                                    |
|----------|---------------------------------------------|
| Light    | Display numbers only, 20px and above        |
| Regular  | Body text, descriptions, flavour            |
| Semibold | Labels, buttons, anything that reads as UI  |
| Bold     | Headings and the one number that matters    |
