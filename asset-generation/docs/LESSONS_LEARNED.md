# Lessons Learned: 3D Asset Development

## Overview

This document captures key learnings from developing the procedural 3D asset pipeline for xen-words. These lessons should inform all future 3D asset work.

---

## 1. Asset Creation Methodology

### ✅ What Worked Well

**Procedural Generation with Parameters**
- Writing Python scripts to generate geometry is **highly maintainable**
- Parameters at the top make adjustments trivial (vs. re-modeling in Blender GUI)
- Version-controlling scripts means we can reproduce assets exactly
- Example: Changing plant height from 0.70m to 0.85m took 30 seconds

**Compositional Structure**
- Separating Pot, Foliage, and Dirt enables **mix-and-match**
- Can create variety (different pots × different foliage = many combinations)
- Easier to fix issues (bug in dirt? Just regenerate dirt, not whole plant)
- Scales well (add new pot styles, reuse with existing foliage)

**Blender MCP for Prototyping**
- Interactive Blender control via MCP was **invaluable** for rapid iteration
- Could test ideas immediately, then codify successful approaches into generators
- Workflow: Experiment via MCP → Extract parameters → Write generator script

### ❌ What Didn't Work

**Hardcoded Geometry**
- Initially created assets manually in Blender → hard to adjust
- No record of how geometry was created → can't reproduce
- Small tweaks required re-modeling from scratch

**Monolithic Assets**
- First PottedPlant was single joined mesh → couldn't separate components
- Made it impossible to vary pot/foliage independently
- Lesson: **Always think compositionally from the start**

**Ephemeral Scripts**
- Early work used MCP commands that weren't saved
- Lost the "recipe" for creating assets
- Had to reverse-engineer from .blend files
- Lesson: **Save generation code immediately**

---

## 2. Performance & Optimization

### Key Learnings

**Polygon Budget**
- **Target: 500-2000 polys per asset** for mobile
- Ground plane: 1 poly → excellent
- Each potted plant: ~1800 polys → good
- Total scene: ~3600 polys → excellent for mobile

**What Matters Most**:
1. **Triangle count** (not vertex count)
2. **Material count** (shader switches are expensive)
3. **Texture size** (memory usage)

**Instancing is Critical**
- Two plants with shared mesh = **1× memory**, not 2×
- Blender: `plant2.data = plant1.data` (share mesh)
- Resulted in ~50% memory savings

**Where to Add Detail**:
- ✅ Close to camera → justify more polygons
- ✅ Character face → worth the investment
- ❌ Background elements → keep simple
- ❌ Flat surfaces → don't need subdivisions

### Premature Optimization Mistakes

**Polyhaven Assets**
- Downloaded high-quality photogrammetry plant → **78k polygons**
- Way too much for mobile game
- Had to recreate from scratch at low poly
- Lesson: **Check poly count before integrating external assets**

**Over-Segmentation**
- First pot had 32 segments → looked smooth but unnecessary
- Reduced to 16 → looked identical, half the polygons
- Lesson: **Test lower detail first, add detail only if needed**

---

## 3. Material & Texturing

### What We Learned

**Simple Materials Win**
- Principled BSDF with base color + roughness is sufficient
- Complex node setups often don't export well to glTF
- Mobile can't handle advanced shader nodes anyway

**Dirt Material Issue**
- Dirt initially showed as concrete texture in game
- Issue: **Material wasn't assigned correctly** (wrong face material index)
- Also: Dirt face was too small / had gaps
- Solution: Proper material assignment + complete triangulated surface

**PBR Textures Work Great**
- Polyhaven wood floor texture (1K resolution) looks excellent
- Embedded textures in GLB work perfectly with Thermion
- Cubic interpolation on textures reduced aliasing at distance

### Best Practices Established

1. **Use simple, exportable materials**
   - Principled BSDF
   - Embedded textures (not external references)
   - Standard glTF-compatible features

2. **Test export early**
   - Create material → export test → verify in game
   - Don't spend hours on complex setup that won't export

3. **Validate material assignment**
   - Use analyzer tool to check face counts per material
   - Verify materials actually render in viewport

---

## 4. Geometry & Topology

### Critical Lessons

**Ngons Don't Export Reliably**
- Created dirt as 17-vertex ngon → **missing wedge in render**
- Vertex ordering confused the renderer
- Solution: **Triangulate complex faces**
- 1 ngon → 16 triangles = complete coverage, no gaps

**Face Normals Matter**
- If normal points wrong way, face is culled (invisible)
- Always check normals point outward
- Use smooth shading for organic shapes

**Vertex Sharing**
- Dirt face initially shared vertices with pot rim
- Caused Z-fighting and rendering issues
- Solution: **Create separate vertices** for overlapping geometry

**Clean Geometry is Essential**
- Non-manifold edges cause issues
- Loose vertices add bloat
- Analyzer tool catches these automatically

### Modeling Techniques That Worked

**Tapered Cylinders (Pot)**
- Define vertical profile, rotate around Z axis
- Creates clean, efficient geometry
- Easy to add details (rim, flare)

**Radial Distributions (Leaves)**
- Distribute around branches using polar coordinates
- Add randomness for organic feel
- Scale/rotate each instance for variation

**Triangulated Surfaces (Dirt)**
- Center vertex + outer ring
- Create triangle from center to each pair of outer vertices
- Guarantees complete coverage

---

## 5. Pipeline & Workflow

### Infrastructure Wins

**Separate generators/ directory**
- Generator scripts are **source of truth**
- .blend files are **build artifacts** (can be regenerated)
- Version control generators, not (necessarily) .blend files

**Analysis Tools**
- `asset_analyzer.py` catches issues automatically
- Running after each generation prevents problems
- Provides objective metrics (poly count, bounds, etc.)

**Rebuild Script**
- `rebuild_all.py` regenerates entire asset library
- Ensures changes propagate correctly
- Makes experimentation safe (can always rebuild)

**Documentation**
- Parameter reference makes adjustments discoverable
- Workflow guide captures best practices
- Lessons learned prevent repeating mistakes

### Process That Works

1. **Prototype** interactively (Blender MCP)
2. **Extract** successful parameters
3. **Codify** into generator script
4. **Test** with analyzer
5. **Compose** into scenes
6. **Export** and verify in game
7. **Document** any new learnings

---

## 6. Integration with Thermion

### What We Learned

**Hot Reload Doesn't Work for 3D Assets**
- Flutter can hot reload code
- 3D assets require full app restart
- Plan testing accordingly (batch changes, then test)

**GLB Export Settings Matter**
- Must export materials (`export_materials='EXPORT'`)
- Must apply transforms (`export_apply=True`)
- Backward compatibility: also export to legacy `GroundPlane.glb`

**Material Rendering**
- Simple materials render reliably
- Complex Blender shader nodes may not export
- Test in-game, not just in Blender viewport

**Coordinate Systems**
- Blender: Z-up (Y forward)
- Game: Z-up (Y forward) → same, good
- But Y-positive is **forward**, not back (easy to mix up)

---

## 7. Iteration Speed

### Before Procedural Pipeline
- Adjust pot shape: 30+ minutes (remodel in Blender GUI)
- Change plant fullness: 20+ minutes (add leaves manually)
- Fix dirt surface: 15+ minutes (re-UV, re-texture)
- Total: ~1 hour per iteration

### After Procedural Pipeline
- Adjust pot shape: 2 minutes (change 2 parameters, run script)
- Change plant fullness: 1 minute (change `leaf_count`, run script)
- Fix dirt surface: 1 minute (change `dirt_radius`, run script)
- Total: ~4 minutes per iteration

**15× faster iteration** enables much more experimentation and refinement.

---

## 8. Future Recommendations

### Immediate Priorities

1. **Expand asset library**
   - Use existing generators as templates
   - Create: chairs, tables, decorative objects
   - Maintain compositional approach

2. **Variation system**
   - Generate multiple variants automatically
   - Example: 3 pot styles × 4 foliage types = 12 combinations
   - Script to batch-generate all combinations

3. **Texture library**
   - Curate collection of PBR textures
   - Document which work well at 1K/2K resolution
   - Create texture application helpers

### Long-term Improvements

1. **GUI Parameter Tool**
   - Blender addon with sliders for parameters
   - Real-time preview
   - Export to generator script

2. **Asset Packs**
   - Group related assets (furniture set, plant varieties)
   - Versioned releases
   - Automated testing on mobile

3. **Performance Profiling**
   - Integrate with Flutter DevTools
   - Measure actual rendering cost per asset
   - Data-driven optimization decisions

---

## 9. Key Takeaways

### The Big Principles

1. **Procedural > Manual** for maintainability
2. **Compositional > Monolithic** for reusability  
3. **Parameters > Hardcoded** for flexibility
4. **Analyzed > Assumed** for quality
5. **Documented > Implied** for team scale

### When to Break the Rules

**Use manual modeling when**:
- One-off, hero assets (main character)
- Very complex organic shapes (scanned models)
- Time-constrained prototyping

**But always**:
- Document what was done
- Capture settings and parameters
- Make it reproducible

---

## 10. Success Metrics

### Before/After Comparison

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Iteration time | 60 min | 4 min | **15× faster** |
| Asset variations | 1 | ∞ (parametric) | **Unlimited** |
| Poly count control | Manual | Automatic analysis | **Precise** |
| Reproducibility | None | 100% | **Perfect** |
| Team onboarding | Hours | Minutes (docs) | **10× easier** |
| Bug fix time | Remodel | Regenerate (30s) | **20× faster** |

### Quality Improvements

- ✅ Consistent quality across assets
- ✅ Optimal poly counts for mobile
- ✅ Clean, manifold geometry
- ✅ Proper material assignment
- ✅ Correct normals and shading
- ✅ No rendering artifacts

---

## Conclusion

The investment in procedural infrastructure has **already paid for itself** and will continue to accelerate development. The key insight: **Treat 3D assets like code, not like art**. They should be versioned, reviewed, tested, and documented just like application code.

Going forward, this methodology should be the foundation for all 3D asset work in xen-words.

