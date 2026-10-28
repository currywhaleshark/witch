# Alley surface textures v1

Tileable surfaces for the lot kit in `game/scripts/field_map.gd` (`SURFACES`). Every source is from
[ambientCG](https://ambientcg.com) under **CC0 1.0** (public domain, no attribution required).
The user approved downloading these six 1K-JPG sets on 2026-10-28.

| Game name | Source | Used on |
|---|---|---|
| `brick` | [Bricks059](https://ambientcg.com/view?id=Bricks059) | red-brick garden walls and piers |
| `block` | [Bricks061](https://ambientcg.com/view?id=Bricks061) | grey cement-block garden walls and piers |
| `plaster` | [Plaster003](https://ambientcg.com/view?id=Plaster003) | house walls, parapets, cut shop wall stubs |
| `concrete` | [Concrete034](https://ambientcg.com/view?id=Concrete034) | kerbs, yards, stairs, copings, floor bands, roof slabs, poles |
| `asphalt` | [Road013A](https://ambientcg.com/view?id=Road013A) | alley floors |
| `metal` | [PaintedMetal014](https://ambientcg.com/view?id=PaintedMetal014) | gate leaves, shutters, doors |

Only the colour and OpenGL normal maps are kept, resized to 512 px. `brick` keeps its colour.
The other five are greyscale, set to one average brightness, with contrast raised for the subtle
sets (values in `manifest.json`). The game multiplies each texture by palette colour ÷ the
manifest `reference` colour, so pieces keep their palette colour on average. Textures are projected
in world space (triplanar), so boxes need no UVs.

The original zips are not kept in the repository. `manifest.json` records each download's SHA-256 and
each derived file's hash. The `.import` files enable mipmaps and lossless compression and mark the
normal maps as normal maps.
