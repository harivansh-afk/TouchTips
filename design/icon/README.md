# App icon

Michelangelo's two hands from the Creation of Adam, Adam bottom-left and God top-right,
rendered as ASCII. White glyphs on black, the app's only two colours.

Source: `hands.jpg`, the "Creation of Adam (Michelangelo) Detail" file on Wikimedia Commons,
public domain. Regenerate with:

```
uv run --with pillow --with numpy --with scipy python3 -c "import generate; generate.final(cols=64, angle=40, scale=1.5, push=0.03, name='icon')"
```

The mask is a saturation-and-warmth threshold on the plaster, hole-filled, two largest
components kept. Edge cells get contour glyphs by gradient direction, interior cells a density
ramp from the fresco's own shading. The two hands are pushed apart along the diagonal so the
gap sits at the centre. 64 columns: fingers resolve at 1024, the silhouette carries at 60 points.
