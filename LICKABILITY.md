# Specification: Convincing Glossy, Translucent Interface Shapes

## 1. Visual Objective

The surface should read as a **thin, molded, translucent object with a polished wet sheen**, rather than as a flat rectangle filled with a gradient.

The characteristic appearance comes from the interaction of:

* a shaped translucent body;
* several independently positioned gradients;
* broad, soft internal reflections;
* narrow specular highlights;
* edge brightening;
* controlled darkening beneath and toward the lower edge;
* subtle optical depth;
* a soft external shadow;
* highlights that conform to the object's geometry rather than simply following its bounding box.

The important principle is:

> **Do not construct the appearance from one vertical gradient. Construct it as several overlapping translucent shapes that imply a curved surface.**

---

## 2. Base Geometry

Every control should begin with a **silhouette appropriate to its physical form**, not a generic rounded rectangle.

### 2.1 Capsule / Pill

Use a true capsule:

* horizontal body;
* semicircular ends;
* radius = approximately half the height;
* no visible corner transition.

For a 120 × 32 px control:

* corner radius: 16 px;
* usable optical body: approximately 112–116 px;
* highlight shapes should terminate before the extreme ends rather than wrapping mechanically around them.

The capsule should appear slightly swollen toward its center.

### 2.2 Circular / Round Button

Treat the button as a shallow convex lens rather than a flat disk.

Use:

1. the circular silhouette;
2. a broad elliptical upper reflection;
3. a smaller concentrated specular region;
4. a lower-body darkening layer;
5. an edge or rim layer.

The internal highlight should **not** be circular. It should generally be elliptical because it represents reflected light on a curved surface.

### 2.3 Rounded Rectangle

Use four separate conceptual regions:

* upper face;
* central body;
* lower transition;
* perimeter.

The corner radius should remain geometrically continuous, but the optical treatment should not be uniform around the perimeter.

The upper corners may be slightly brighter than the lower corners.

### 2.4 Small Rectangular Controls

For compact controls, reduce the number of visible optical layers rather than simply scaling everything down.

At small sizes:

* retain the broad upper reflection;
* retain a subtle lower darkening;
* retain a thin edge highlight;
* remove or substantially weaken secondary highlights.

Too many gradients at small dimensions produce noise instead of gloss.

---

## 3. Primary Body Gradient

The body establishes translucency and volume.

Use a **multi-stop vertical gradient**, but do not make it responsible for the entire appearance.

Recommended conceptual distribution:

| Position | Appearance         | Purpose                   |
| -------- | ------------------ | ------------------------- |
| 0–8%     | bright translucent | upper illuminated edge    |
| 8–25%    | light body         | transition from highlight |
| 25–60%   | medium body        | primary material          |
| 60–82%   | slightly darker    | curvature                 |
| 82–100%  | darker translucent | lower volume              |

The gradient should be relatively low contrast.

A realistic glossy object should derive most of its perceived depth from **overlapping light shapes**, not from a dramatic light-to-dark body gradient.

---

## 4. Upper Translucent Reflection

The most important secondary shape is a **large translucent reflection occupying the upper portion of the object**.

### Shape

For horizontal pills and rounded rectangles:

* use a rounded, horizontally elongated shape;
* approximately 55–90% of the object's width;
* approximately 25–45% of its height;
* centered horizontally;
* positioned roughly 5–20% below the upper boundary.

For circles:

* use a broad ellipse;
* approximately 55–75% of the diameter;
* slightly wider than tall;
* positioned above the vertical center.

### Gradient

The reflection itself should have:

* strongest opacity near its upper/central region;
* gradual transparency toward its lower boundary;
* soft transparency toward the sides.

It should **fade into the body**, rather than ending at a visible geometric boundary.

Conceptually:

`opaque-ish → translucent → nearly invisible`

rather than:

`white → transparent`

The highlight should usually inherit a slightly warm or neutral tint from the material instead of being pure white.

---

## 5. Secondary Curved Highlight

Add a second, narrower shape inside the primary reflection.

This represents a concentrated light band.

For a pill:

* elongated horizontally;
* slightly curved or bowed;
* approximately 45–75% of the total width;
* only 5–15% of the total height;
* positioned within the upper third.

For a circular surface:

* use a curved crescent or flattened ellipse;
* avoid a straight horizontal stripe.

The shape should have very low opacity at its ends and higher opacity around its center.

This layer is responsible for the characteristic **wet, polished sensation**.

---

## 6. Lower-Surface Gradient

The bottom portion should not merely be a darker version of the top.

Add a separate translucent shape representing the curvature turning away from the light.

For pills and rounded rectangles:

* use a horizontally elongated rounded shape;
* position it approximately 65–95% down the body;
* make it substantially softer than the upper reflection;
* allow its opacity to increase toward the lower edge.

For circular buttons:

* use a broad lower ellipse;
* slightly narrower than the upper reflection;
* centered horizontally;
* partially clipped by the circular silhouette.

The result should suggest:

**light → curved surface → light falls away → darker underside**

rather than a simple two-color gradient.

---

## 7. Perimeter / Rim Light

A thin translucent perimeter should provide separation from the background.

Do not use a uniformly bright border.

Instead, construct an optical rim with directionality:

* strongest near the upper edge;
* moderately visible on upper-left and upper-right curvature;
* weak along the sides;
* nearly absent at the bottom;
* optionally reappearing very subtly at the lowest edge.

A useful mental model is that the rim is a **reflection of the environment**, not an outline.

### Recommended treatment

Use a thin inset shape or stroke with:

* low opacity;
* soft antialiasing;
* brighter upper arc;
* progressively transparent lower arc.

For a circular button, the upper semicircle can be noticeably brighter than the lower semicircle.

---

## 8. Edge Compression

To prevent the object from looking like a flat sticker, darken the immediate interior near portions of the perimeter.

This should be extremely subtle.

Use an inner-edge gradient:

* transparent toward the center;
* slightly darker toward selected edges;
* strongest around lower corners and lower perimeter.

The combination of:

**bright outer rim + slightly darker interior edge**

creates the impression of a curved wall.

---

## 9. Translucent Overlays

The material should permit some interaction with the underlying background.

Do not treat translucency as simple alpha reduction.

Use several alpha-bearing layers:

1. base material;
2. broad reflection;
3. concentrated reflection;
4. lower curvature;
5. edge reflection;
6. optional environmental tint.

The background should remain faintly perceptible through the body, especially in less illuminated regions.

The translucency should be **optical**, not foggy.

Avoid enough transparency to make the control appear glass-like. The desired impression is closer to a **colored, polished, semi-translucent molded surface**.

---

## 10. Highlight Geometry by Shape

### Capsule

Use:

* large upper capsule/ellipse;
* narrow internal horizontal highlight;
* faint lower capsule;
* upper rim;
* lower inner darkening.

The highlights should follow the capsule's long axis.

### Circle

Use:

* broad upper ellipse;
* offset secondary ellipse;
* small curved specular patch;
* faint lower ellipse;
* asymmetric perimeter reflection.

The highlight should be slightly biased toward one side rather than mathematically centered.

### Rounded Rectangle

Use:

* broad rounded upper reflection;
* narrower central highlight;
* faint lower reflection;
* selective corner reflections;
* continuous but asymmetric perimeter light.

### Small Circular Indicator

Use:

* radial-ish body shading;
* upper-left elliptical reflection;
* tiny specular point;
* lower-right darkening.

The specular point should be small enough to remain a suggestion rather than a visible white dot.

---

## 11. Direction of Light

All controls in a visual system should share a common virtual light source.

A good default is:

**upper-left/front → lower-right/back**

This means:

* upper-left regions receive stronger reflections;
* upper surfaces are brighter;
* lower-right regions become slightly darker;
* specular highlights are displaced consistently;
* shadows fall subtly toward the lower-right.

Do not independently center every highlight.

Consistency between controls is critical to making them appear to exist in the same physical environment.

---

## 12. Specular Highlight

The final specular highlight should be much smaller than the broad reflection.

Use one of:

* a small elongated ellipse;
* a curved sliver;
* a short soft arc;
* a small irregular rounded patch.

Its opacity should be low enough that it feels like reflected light rather than painted decoration.

Avoid:

* hard white streaks;
* pure-white borders;
* perfectly centered highlights;
* multiple equally bright spots;
* mirror-like reflections.

The specular highlight should have a **soft core with an even softer halo**.

---

## 13. Corner Treatment

Corners require special treatment because they are where a flat rendering most easily becomes obvious.

For rounded rectangles:

* brighten the upper corner curvature slightly;
* let the highlight follow the corner arc;
* avoid making the entire corner uniformly bright;
* darken the inner lower corner subtly.

The transition must remain continuous.

For very small radii, simplify the optical treatment rather than trying to reproduce every highlight layer.

---

## 14. Optical Center vs. Geometric Center

Do not assume that the visually brightest point belongs at the geometric center.

The perceived center of a glossy control is generally shifted upward because:

* the upper reflection is brighter;
* the lower region is darker;
* the specular highlight is displaced;
* the edge reflection changes apparent volume.

This asymmetry is essential.

A perfectly symmetric gradient tends to look synthetic.

---

## 15. External Shadow

The shadow should describe **contact and elevation**, not dramatic depth.

Use two conceptual shadows:

### Contact shadow

* very close to the object;
* narrow;
* relatively dark;
* strongly blurred;
* directly beneath the control.

### Ambient shadow

* larger;
* much softer;
* lower opacity;
* extending farther from the object.

The ambient shadow should be especially subtle for small controls.

Avoid a large black drop shadow. It makes the object appear detached rather than physically embedded in the interface.

---

## 16. Background Interaction

A translucent glossy object becomes much more convincing when its appearance changes slightly according to what lies behind it.

The body may contain:

* faint background luminance;
* subtle environmental tint;
* slightly stronger contrast around the edges;
* softened background detail.

However, the underlying content should never become clearly visible unless the material is intentionally glass-like.

The goal is:

**background influence without background visibility.**

---

## 17. Alpha Hierarchy

A useful relative hierarchy is:

1. **Base body:** strongest overall opacity.
2. **Broad upper reflection:** moderate opacity.
3. **Lower curvature:** low-to-moderate opacity.
4. **Rim:** low opacity.
5. **Secondary highlight:** low opacity.
6. **Specular highlight:** very low area, potentially higher local opacity.
7. **Edge darkening:** extremely low opacity.

Large shapes should generally be faint.

Small shapes may be stronger.

This is analogous to real reflected light: broad reflections are diffuse, while concentrated reflections have greater local intensity.

---

## 18. Avoiding the "Gradient Button" Failure Mode

Do not use:

* one top-to-bottom gradient;
* one white stripe;
* a uniform white border;
* a single drop shadow;
* identical highlights on every shape;
* perfectly symmetrical illumination;
* hard-edged translucent overlays;
* pure white glossy regions;
* excessive transparency;
* excessive contrast.

The resulting control should never look like:

> colored rectangle + white stripe + shadow.

Instead it should read as:

> **a small three-dimensional translucent object whose surface happens to have been molded into a control shape.**

---

## 19. Recommended Layer Stack

From back to front:

```text
background
    ↓
ambient shadow
    ↓
contact shadow
    ↓
outer silhouette / base material
    ↓
body luminance gradient
    ↓
lower curvature darkening
    ↓
broad upper translucent reflection
    ↓
secondary curved reflection
    ↓
localized specular highlight
    ↓
selective perimeter reflection
    ↓
subtle inner-edge darkening
```

Every layer should be clipped to the master silhouette.

---

## 20. Realism Rules

### Rule 1 — Highlights have area

Real reflected light is rarely a one-pixel line. Prefer broad, low-opacity shapes.

### Rule 2 — Brightness is directional

The upper region should generally receive more light than the lower region.

### Rule 3 — Transparency is layered

Do not encode translucency solely into the base fill.

### Rule 4 — Geometry controls light

A circular object receives curved reflections; a pill receives elongated reflections; a rounded rectangle receives reflections that follow its corners.

### Rule 5 — Imperfect symmetry looks more physical

Slightly offset highlights and asymmetric edge illumination are preferable to perfectly centered gradients.

### Rule 6 — Contrast decreases toward the edges

Most internal reflections should soften before reaching the silhouette.

### Rule 7 — The brightest region should be small

Large bright areas flatten the object.

### Rule 8 — Dark regions should remain translucent

The underside should feel shaded, not painted black.

### Rule 9 — Every highlight needs a fade

Avoid abrupt alpha transitions.

### Rule 10 — The object must work at multiple scales

At large sizes, several optical layers can be visible. At small sizes, merge them perceptually into a simpler highlight system.

---

## 21. Perceived Material Target

The final result should evoke the following physical qualities simultaneously:

* smooth;
* slightly convex;
* polished;
* soft-edged;
* translucent;
* colorful;
* moist-looking without appearing wet;
* reflective without becoming metallic;
* dimensional without looking 3D-rendered;
* luminous without glowing.

The ideal surface appears almost **edible or touchable**: a viewer should be able to imagine pressing it and seeing the glossy surface deform slightly.

That impression comes primarily from **curvature implied by light**, not from stronger colors, stronger shadows, or more dramatic gradients.

## 22. Implementation Principle

Treat every control as a **silhouette plus an optical lighting model**.

The silhouette determines *what the object is*.

The overlapping translucent shapes determine *how its surface bends light*.

The shadows determine *where the object sits*.

The shared light direction determines *whether the entire interface feels physically coherent*.

The realism target is reached when these layers become visually inseparable: the viewer should perceive a single molded, polished surface rather than a collection of gradients.
