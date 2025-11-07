"""
Procedural Backdrop Generator

Creates three separate shoji-style backdrop panels:
- TopPanel: Full-width static top panel
- BackdropLeft: Left side panel going to floor
- BackdropRight: Right side panel going to floor

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python generate_backdrop.py
"""

import bpy
import bmesh
import math
from pathlib import Path
import numpy as np

# ============================================================================
# PARAMETERS - Adjust these to change the backdrop
# ============================================================================

BACKDROP_CONFIG = {
    # Overall dimensions
    'total_width': 6.0,              # Total width of backdrop area (meters)
    'total_height': 5.5,             # Total height of backdrop (meters) - increased from 5.0
    
    # Top panel (static, full width)
    'top_panel_height_ratio': 0.15,   # Top panel takes ~15% of height (reduced from 18% to make side panels taller)
    
    # Side panels (left and right)
    'num_panels_horizontal': 2,      # 2 panels per side (left and right)
    'num_panels_vertical': 2,        # 2 horizontal rows per side
    'grid_subdivisions': 6,           # More subdivisions for finer grid (6x6 = 36 per panel)
    
    # Opening configuration (gap between left and right panels)
    'opening_width': 2.0,             # Width of opening in meters (center gap)
    
    # Material colors
    'frame_color': (0.35, 0.25, 0.18, 1.0),  # Darker wood tone (better contrast with floor and panels)
    'panel_color': (1.0, 1.0, 0.99, 1.0),    # White paper (pure white)
    'top_panel_color': (1.0, 1.0, 0.99, 1.0), # Top panel color (same as panels)
    'frame_roughness': 0.7,         # Slight wood texture
    'panel_roughness': 0.95,        # Very matte, paper-like
}

# ============================================================================
# GENERATOR FUNCTIONS
# ============================================================================

def create_panel_geometry(width, height):
    """Create a simple flat plane for a panel."""
    mesh = bpy.data.meshes.new("PanelMesh")
    bm = bmesh.new()
    
    # Create flat plane
    v1 = bm.verts.new((-width/2, 0, height/2))   # Top-left
    v2 = bm.verts.new((width/2, 0, height/2))   # Top-right
    v3 = bm.verts.new((width/2, 0, -height/2))   # Bottom-right
    v4 = bm.verts.new((-width/2, 0, -height/2))   # Bottom-left
    
    # Create face
    face = bm.faces.new([v1, v2, v3, v4])
    
    # Flip face so normal points toward camera (-Y direction)
    face.normal_update()
    if face.normal.y > 0:
        face.normal_flip()
    
    # Create UV layer
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for loop in face.loops:
        u = (loop.vert.co.x + width/2) / width
        v = (loop.vert.co.z + height/2) / height
        loop[uv_layer].uv = (u, v)
    
    face.smooth = True
    
    bm.to_mesh(mesh)
    bm.free()
    
    return mesh

def create_top_panel_texture(config):
    """Create texture for the top panel (same shoji pattern as side panels, matching panel size exactly)."""
    # Calculate panel size to match side panels exactly
    # Side panels: 2.0m wide, 2 panels horizontally = 1.0m per panel
    # Top panel: 6.0m wide, should have 6 panels horizontally (6.0m / 1.0m = 6 panels)
    side_panel_width = (config['total_width'] - config['opening_width']) / 2.0
    panel_width = side_panel_width / config['num_panels_horizontal']  # 2.0m / 2 = 1.0m per panel
    num_panels_w = int(config['total_width'] / panel_width)  # 6.0m / 1.0m = 6 panels
    num_panels_h = 1  # Just one row for top panel
    
    # Calculate texture size to match pixel density of side panels EXACTLY
    # Side panels: 2.0m wide, 1024px texture, 2 panels = 512px per panel
    # Top panel: 6.0m wide, 6 panels = needs 6 × 512px = 3072px wide texture
    # Use 3072px (exact match) or round up to 4096px but scale frame width proportionally
    side_panel_texture_width = 1024
    side_panel_pixels_per_panel = side_panel_texture_width // config['num_panels_horizontal']  # 1024 / 2 = 512px per panel
    texture_width = num_panels_w * side_panel_pixels_per_panel  # 6 × 512 = 3072px
    texture_height = 1024  # Same height as side panels
    
    # Scale frame width proportionally to match side panels
    # Side panels: frame_width_px = 6px at 1024px texture width
    # Top panel: frame_width_px should scale with texture width ratio
    scale_factor = texture_width / side_panel_texture_width  # 3072 / 1024 = 3.0
    base_frame_width_px = 6
    frame_width_px = int(base_frame_width_px * scale_factor)  # 6 × 3 = 18px
    beam_height_px = frame_width_px * 3  # Scale beam proportionally too
    
    grid_subdivisions = config['grid_subdivisions']
    
    texture = np.ones((texture_height, texture_width, 4), dtype=np.float32)
    frame_color = np.array(config['frame_color'][:3])
    panel_color = np.array(config['panel_color'][:3])
    
    # Calculate panel area (below top beam)
    panels_area_height_px = texture_height - beam_height_px
    panel_size_w = texture_width // num_panels_w
    panel_size_h = panels_area_height_px // num_panels_h
    small_rect_w = panel_size_w // grid_subdivisions
    small_rect_h = panel_size_h // grid_subdivisions
    
    # Start with all white (panels)
    texture[:, :, :3] = panel_color
    
    # Draw dark wood beam at top
    texture[0:beam_height_px, :, :3] = frame_color
    
    # Draw panels below beam (same pattern as side panels, exact same panel size)
    for panel_y_idx in range(num_panels_h):
        for panel_x_idx in range(num_panels_w):
            panel_x_start = panel_x_idx * panel_size_w
            panel_x_end = (panel_x_idx + 1) * panel_size_w
            panel_y_start = beam_height_px + panel_y_idx * panel_size_h
            panel_y_end = panel_y_start + panel_size_h
            
            # Outer frame
            outer_frame = frame_width_px * 2
            # Top frame (already has beam above)
            if panel_y_idx == 0:
                pass
            # Bottom frame
            if panel_y_idx == num_panels_h - 1:
                texture[panel_y_end - outer_frame:panel_y_end, panel_x_start:panel_x_end, :3] = frame_color
            # Left frame
            if panel_x_idx == 0:
                texture[panel_y_start:panel_y_end, panel_x_start:panel_x_start + outer_frame, :3] = frame_color
            # Right frame
            if panel_x_idx == num_panels_w - 1:
                texture[panel_y_start:panel_y_end, panel_x_end - outer_frame:panel_x_end, :3] = frame_color
            
            # Inner dividers between panels (vertical)
            if panel_x_idx < num_panels_w - 1:
                divider_x = panel_x_end - frame_width_px // 2
                texture[panel_y_start:panel_y_end, divider_x - frame_width_px // 2:divider_x + frame_width_px // 2, :3] = frame_color
            
            # Inner dividers between panels (horizontal) - not needed for single row, but keep for consistency
            if panel_y_idx < num_panels_h - 1:
                divider_y = panel_y_end - frame_width_px // 2
                texture[divider_y - frame_width_px // 2:divider_y + frame_width_px // 2, panel_x_start:panel_x_end, :3] = frame_color
            
            # Draw grid within each panel (same as side panels - exact same grid cell size)
            for grid_y_idx in range(grid_subdivisions):
                for grid_x_idx in range(grid_subdivisions):
                    grid_x_start = panel_x_start + grid_x_idx * small_rect_w
                    grid_x_end = grid_x_start + small_rect_w
                    grid_y_start = panel_y_start + grid_y_idx * small_rect_h
                    grid_y_end = grid_y_start + small_rect_h
                    
                    if grid_x_end > panel_x_end or grid_y_end > panel_y_end:
                        continue
                    
                    # Draw frame lines around each small rectangle (same as side panels)
                    if grid_y_idx > 0:
                        texture[grid_y_start - frame_width_px // 2:grid_y_start + frame_width_px // 2, 
                               grid_x_start:grid_x_end, :3] = frame_color
                    if grid_y_idx < grid_subdivisions - 1:
                        texture[grid_y_end - frame_width_px // 2:grid_y_end + frame_width_px // 2, 
                               grid_x_start:grid_x_end, :3] = frame_color
                    if grid_x_idx > 0:
                        texture[grid_y_start:grid_y_end, 
                               grid_x_start - frame_width_px // 2:grid_x_start + frame_width_px // 2, :3] = frame_color
                    if grid_x_idx < grid_subdivisions - 1:
                        texture[grid_y_start:grid_y_end, 
                               grid_x_end - frame_width_px // 2:grid_x_end + frame_width_px // 2, :3] = frame_color
    
    # All opaque
    texture[:, :, 3] = 1.0
    
    return texture

def create_side_panel_texture(config, is_left=True):
    """Create texture for left or right side panel (with grid)."""
    texture_size = 1024
    num_panels_w = config['num_panels_horizontal']
    num_panels_h = config['num_panels_vertical']
    grid_subdivisions = config['grid_subdivisions']
    frame_width_px = 6
    beam_height_px = frame_width_px * 3
    
    texture = np.ones((texture_size, texture_size, 4), dtype=np.float32)
    frame_color = np.array(config['frame_color'][:3])
    panel_color = np.array(config['panel_color'][:3])
    
    # Calculate panel area (below top beam)
    panels_area_height_px = texture_size - beam_height_px
    panel_size_w = texture_size // num_panels_w
    panel_size_h = panels_area_height_px // num_panels_h
    small_rect_w = panel_size_w // grid_subdivisions
    small_rect_h = panel_size_h // grid_subdivisions
    
    # Start with all white (panels)
    texture[:, :, :3] = panel_color
    
    # Draw dark wood beam at top
    texture[0:beam_height_px, :, :3] = frame_color
    
    # Draw panels below beam
    for panel_y_idx in range(num_panels_h):
        for panel_x_idx in range(num_panels_w):
            panel_x_start = panel_x_idx * panel_size_w
            panel_x_end = (panel_x_idx + 1) * panel_size_w
            panel_y_start = beam_height_px + panel_y_idx * panel_size_h
            panel_y_end = panel_y_start + panel_size_h
            
            # Outer frame
            outer_frame = frame_width_px * 2
            # Top frame (first row - already has beam above)
            if panel_y_idx == 0:
                pass
            # Bottom frame
            if panel_y_idx == num_panels_h - 1:
                texture[panel_y_end - outer_frame:panel_y_end, panel_x_start:panel_x_end, :3] = frame_color
            # Left frame
            if panel_x_idx == 0:
                texture[panel_y_start:panel_y_end, panel_x_start:panel_x_start + outer_frame, :3] = frame_color
            # Right frame
            if panel_x_idx == num_panels_w - 1:
                texture[panel_y_start:panel_y_end, panel_x_end - outer_frame:panel_x_end, :3] = frame_color
            
            # Inner dividers between panels (vertical)
            if panel_x_idx < num_panels_w - 1:
                divider_x = panel_x_end - frame_width_px // 2
                texture[panel_y_start:panel_y_end, divider_x - frame_width_px // 2:divider_x + frame_width_px // 2, :3] = frame_color
            
            # Inner dividers between panels (horizontal)
            if panel_y_idx < num_panels_h - 1:
                divider_y = panel_y_end - frame_width_px // 2
                texture[divider_y - frame_width_px // 2:divider_y + frame_width_px // 2, panel_x_start:panel_x_end, :3] = frame_color
            
            # Draw grid within each panel
            for grid_y_idx in range(grid_subdivisions):
                for grid_x_idx in range(grid_subdivisions):
                    grid_x_start = panel_x_start + grid_x_idx * small_rect_w
                    grid_x_end = grid_x_start + small_rect_w
                    grid_y_start = panel_y_start + grid_y_idx * small_rect_h
                    grid_y_end = grid_y_start + small_rect_h
                    
                    if grid_x_end > panel_x_end or grid_y_end > panel_y_end:
                        continue
                    
                    # Draw frame lines around each small rectangle
                    if grid_y_idx > 0:
                        texture[grid_y_start - frame_width_px // 2:grid_y_start + frame_width_px // 2, 
                               grid_x_start:grid_x_end, :3] = frame_color
                    if grid_y_idx < grid_subdivisions - 1:
                        texture[grid_y_end - frame_width_px // 2:grid_y_end + frame_width_px // 2, 
                               grid_x_start:grid_x_end, :3] = frame_color
                    if grid_x_idx > 0:
                        texture[grid_y_start:grid_y_end, 
                               grid_x_start - frame_width_px // 2:grid_x_start + frame_width_px // 2, :3] = frame_color
                    if grid_x_idx < grid_subdivisions - 1:
                        texture[grid_y_start:grid_y_end, 
                               grid_x_end - frame_width_px // 2:grid_x_end + frame_width_px // 2, :3] = frame_color
    
    # All opaque
    texture[:, :, 3] = 1.0
    
    return texture

def create_panel_material(texture_data, name):
    """Create material with shoji texture."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    # Create image in Blender
    image = bpy.data.images.new(name=f"{name}Texture", width=texture_data.shape[1], height=texture_data.shape[0])
    image.pixels = texture_data.flatten()
    image.pack()
    
    # Create image texture node
    tex_image = nodes.new(type='ShaderNodeTexImage')
    tex_image.location = (0, 0)
    tex_image.image = image
    
    # Connect UV coordinates
    tex_coord = nodes.new(type='ShaderNodeTexCoord')
    tex_coord.location = (-200, 0)
    mat.node_tree.links.new(tex_coord.outputs['UV'], tex_image.inputs['Vector'])
    
    # Create Principled BSDF
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    bsdf.inputs['Roughness'].default_value = 0.95
    bsdf.inputs['Metallic'].default_value = 0.0
    bsdf.inputs['Alpha'].default_value = 1.0
    
    # Connect texture color to base color
    mat.node_tree.links.new(tex_image.outputs['Color'], bsdf.inputs['Base Color'])
    
    # Set material to OPAQUE
    mat.blend_method = 'OPAQUE'
    mat.use_backface_culling = False
    
    # Output
    output = nodes.new(type='ShaderNodeOutputMaterial')
    output.location = (500, 0)
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    return mat

def generate_backdrop(config=BACKDROP_CONFIG, output_path=None):
    """
    Generate three separate shoji-style backdrop panels.
    
    Args:
        config: Configuration dictionary
        output_path: Optional path to save .blend file
    
    Returns:
        Tuple of (top_panel, left_panel, right_panel) objects
    """
    print(f"\n=== GENERATING SHOJI BACKDROP (3 OBJECTS) ===")
    print(f"  Total width: {config['total_width']}m")
    print(f"  Total height: {config['total_height']}m")
    print(f"  Opening width: {config['opening_width']}m")
    
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Calculate dimensions
    total_width = config['total_width']
    total_height = config['total_height']
    opening_width = config['opening_width']
    top_panel_height = total_height * config['top_panel_height_ratio']
    side_panel_height = total_height - top_panel_height
    
    # Calculate side panel width (each side gets half of remaining width after opening)
    side_panel_width = (total_width - opening_width) / 2.0
    
    # 1. Create TOP PANEL (full width, above everything, resting on top of side panels)
    print(f"\nCreating top panel...")
    top_mesh = create_panel_geometry(total_width, top_panel_height)
    top_panel = bpy.data.objects.new("TopPanel", top_mesh)
    bpy.context.collection.objects.link(top_panel)
    top_texture = create_top_panel_texture(config)
    top_mat = create_panel_material(top_texture, "TopPanelMaterial")
    top_panel.data.materials.append(top_mat)
    # Position: resting on top of side panels
    # Side panels go from floor (-total_height/2) to top (-total_height/2 + side_panel_height)
    # Top panel should sit on top: its bottom edge should align with side panels' top edge
    side_panel_top_z = -total_height / 2 + side_panel_height  # Top edge of side panels
    top_panel_bottom_z = side_panel_top_z  # Top panel bottom aligns with side panel top
    top_panel_z = top_panel_bottom_z + top_panel_height / 2  # Center of top panel
    top_panel.location = (0, 0, top_panel_z)  # Same Y depth as side panels (Y=0)
    print(f"  ✓ Created top panel: {total_width}m × {top_panel_height}m (resting on side panels)")
    
    # 2. Create LEFT PANEL (goes to floor)
    print(f"\nCreating left panel...")
    left_mesh = create_panel_geometry(side_panel_width, side_panel_height)
    left_panel = bpy.data.objects.new("BackdropLeft", left_mesh)
    bpy.context.collection.objects.link(left_panel)
    left_texture = create_side_panel_texture(config, is_left=True)
    left_mat = create_panel_material(left_texture, "BackdropLeftMaterial")
    left_panel.data.materials.append(left_mat)
    # Position: left side, below top panel
    left_x = -(total_width / 2 - side_panel_width / 2)  # Left edge aligned with total width
    left_z = -total_height / 2 + side_panel_height / 2  # Bottom aligned with floor
    left_panel.location = (left_x, 0, left_z)
    print(f"  ✓ Created left panel: {side_panel_width}m × {side_panel_height}m")
    
    # 3. Create RIGHT PANEL (goes to floor)
    print(f"\nCreating right panel...")
    right_mesh = create_panel_geometry(side_panel_width, side_panel_height)
    right_panel = bpy.data.objects.new("BackdropRight", right_mesh)
    bpy.context.collection.objects.link(right_panel)
    right_texture = create_side_panel_texture(config, is_left=False)
    right_mat = create_panel_material(right_texture, "BackdropRightMaterial")
    right_panel.data.materials.append(right_mat)
    # Position: right side, below top panel
    right_x = total_width / 2 - side_panel_width / 2  # Right edge aligned with total width
    right_z = -total_height / 2 + side_panel_height / 2  # Bottom aligned with floor
    right_panel.location = (right_x, 0, right_z)
    print(f"  ✓ Created right panel: {side_panel_width}m × {side_panel_height}m")
    
    # Stats
    total_polys = len(top_panel.data.polygons) + len(left_panel.data.polygons) + len(right_panel.data.polygons)
    print(f"\n  ✓ Total: {total_polys} polygons (3 objects)")
    
    # Save if path provided
    if output_path:
        bpy.ops.wm.save_as_mainfile(filepath=output_path)
        print(f"  ✓ Saved: {output_path}")
    
    return (top_panel, left_panel, right_panel)

def main():
    """Main function for standalone execution."""
    # Determine output path
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    output_path = str(script_dir / "assets" / "models" / "library" / "Backdrop.blend")
    
    # Generate backdrop
    generate_backdrop(BACKDROP_CONFIG, output_path)
    
    print(f"\n✅ Backdrop generation complete\n")

if __name__ == "__main__":
    main()
