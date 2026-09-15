# Page art

Two images for https://mannixa.itch.io/fairwayfiends, and the script that makes
them.

| file               | size     | where it goes on itch                          |
| ------------------ | -------- | ---------------------------------------------- |
| `itch_cover.png`   | 630x500  | Edit game -> **Cover image**. Shown in browse, search and embeds, so it has to work as a thumbnail. |
| `itch_banner.png`  | 1920x600 | Top of the **description** body. itch has no dedicated banner field; it is just the first image in the text. |
| `itch_background.png` | 512x512 | Edit theme -> **Background image**, set to repeat. Tiles seamlessly. |

Theme colours worth setting alongside the background, so the page still looks
deliberate before the image loads and on a monitor wider than the tile:

| setting     | value     | why                                              |
| ----------- | --------- | ------------------------------------------------ |
| Background  | `#101d14` | The same deep green the tile is built on.        |
| Text        | `#f2f5ec` | `Palette.INK`.                                   |
| Link        | `#f0c860` | `Palette.GOLD`, the colour a combination fires in. |

Both are built from a real course plate rather than drawn, because the art in
this game *is* the course -- a banner illustrating something else would be
advertising a different game.

## Remaking them

    Godot_console.exe --resolution 2560x800 --path . --script res://tools/banner_shot.gd
    python press/compose.py

The background is a separate, quicker job:

    Godot_console.exe --headless --path . --script res://tools/page_background.gd

`banner_shot.gd` writes four candidate plates to `user://` with the heads-up
display hidden and the camera framed by hand; `compose.py` takes one of them and
lays the wordmark, the tagline and the strapline over it. Which plate looks good
is a matter of taste and cannot be asserted, so it prints all four and you pick.
