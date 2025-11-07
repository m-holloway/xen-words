"""
Download and apply Polyhaven texture to backdrop
Uses Polyhaven's API to get correct download URLs
"""
import bpy
import urllib.request
import json
import tempfile
import os

def download_polyhaven_texture(texture_id, resolution="1k"):
    """Download Polyhaven texture using API to get correct URLs."""
    # Polyhaven API endpoint
    api_url = f"https://api.polyhaven.com/files/{texture_id}"
    
    try:
        # Get file info from API
        with urllib.request.urlopen(api_url) as response:
            data = json.loads(response.read())
        
        # Get texture maps - API structure: {"Diffuse": {"1k": {"jpg": {"url": ...}}}}
        maps = {}
        temp_dir = tempfile.mkdtemp()
        
        # Map names in API vs what we need
        map_mapping = {
            'Diffuse': 'diffuse',
            'nor_dx': 'normal',  # Fixed: API uses 'nor_dx' not 'NormalDX'
            'Rough': 'roughness',  # Fixed: API uses 'Rough' not 'Roughness'
            'AO': 'ao',
        }
        
        # Download each available map
        for api_map_name, map_key in map_mapping.items():
            if api_map_name in data and resolution in data[api_map_name]:
                if 'jpg' in data[api_map_name][resolution]:
                    url = data[api_map_name][resolution]['jpg']['url']
                    try:
                        filepath = os.path.join(temp_dir, f"{texture_id}_{map_key}.jpg")
                        urllib.request.urlretrieve(url, filepath)
                        
                        # Load into Blender
                        img = bpy.data.images.load(filepath)
                        img.name = f"{texture_id}_{map_key}"
                        maps[map_key] = img
                        print(f"  ✓ Downloaded {map_key}")
                    except Exception as e:
                        print(f"  ⚠️ Failed {map_key}: {e}")
        
        return maps
            
    except Exception as e:
        print(f"Error accessing API: {e}")
        import traceback
        traceback.print_exc()
        return {}

def create_material_from_maps(texture_id, maps):
    """Create Principled BSDF material from texture maps."""
    mat = bpy.data.materials.new(name=texture_id)
    mat.use_nodes = True
    
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.location = (0, 0)
    
    # UV coordinates
    tex_coord = nodes.new(type='ShaderNodeTexCoord')
    tex_coord.location = (-600, 0)
    
    # Diffuse
    if 'diffuse' in maps:
        tex_diff = nodes.new(type='ShaderNodeTexImage')
        tex_diff.location = (-400, 0)
        tex_diff.image = maps['diffuse']
        mat.node_tree.links.new(tex_coord.outputs['UV'], tex_diff.inputs['Vector'])
        mat.node_tree.links.new(tex_diff.outputs['Color'], bsdf.inputs['Base Color'])
    
    # Roughness
    if 'roughness' in maps:
        tex_rough = nodes.new(type='ShaderNodeTexImage')
        tex_rough.location = (-400, -200)
        tex_rough.image = maps['roughness']
        # Set to non-color (for roughness/normal maps)
        maps['roughness'].colorspace_settings.name = 'Non-Color'
        mat.node_tree.links.new(tex_coord.outputs['UV'], tex_rough.inputs['Vector'])
        mat.node_tree.links.new(tex_rough.outputs['Color'], bsdf.inputs['Roughness'])
    
    # Normal
    if 'normal' in maps:
        tex_normal = nodes.new(type='ShaderNodeTexImage')
        tex_normal.location = (-400, -400)
        tex_normal.image = maps['normal']
        # Set to non-color
        maps['normal'].colorspace_settings.name = 'Non-Color'
        
        normal_map = nodes.new(type='ShaderNodeNormalMap')
        normal_map.location = (-200, -400)
        mat.node_tree.links.new(tex_coord.outputs['UV'], tex_normal.inputs['Vector'])
        mat.node_tree.links.new(tex_normal.outputs['Color'], normal_map.inputs['Color'])
        mat.node_tree.links.new(normal_map.outputs['Normal'], bsdf.inputs['Normal'])
    
    # AO (optional - can multiply with base color)
    if 'ao' in maps:
        tex_ao = nodes.new(type='ShaderNodeTexImage')
        tex_ao.location = (-400, -600)
        tex_ao.image = maps['ao']
        # Set to non-color
        maps['ao'].colorspace_settings.name = 'Non-Color'
        # Can multiply with base color for better shadows
        # For simplicity, we'll skip this for now
    
    output = nodes.new(type='ShaderNodeOutputMaterial')
    output.location = (200, 0)
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    return mat

# Main
backdrop_path = "/Users/michaelholloway/dev/xen-words/assets/models/library/Backdrop.blend"
bpy.ops.wm.open_mainfile(filepath=backdrop_path)

backdrop = bpy.data.objects.get("Backdrop")
if backdrop:
    # Try lighter texture options
    texture_options = ["plastered_wall", "beige_wall_002", "beige_wall_001"]
    texture_id = texture_options[0]  # Start with plastered_wall (likely lighter)
    
    print(f"\n=== DOWNLOADING POLYHAVEN TEXTURE ===")
    print(f"Texture: {texture_id} (1K resolution)")
    
    maps = download_polyhaven_texture(texture_id, "1k")
    
    if maps:
        mat = create_material_from_maps(texture_id, maps)
        
        # Lighten the diffuse texture if it's too dark
        if 'diffuse' in maps:
            # Increase brightness by mixing with white
            nodes = mat.node_tree.nodes
            
            # Find BSDF node
            bsdf = None
            for node in nodes:
                if node.type == 'BSDF_PRINCIPLED':
                    bsdf = node
                    break
            
            # Find diffuse texture node
            tex_diff = None
            for node in nodes:
                if node.type == 'TEX_IMAGE' and 'diffuse' in node.image.name.lower():
                    tex_diff = node
                    break
            
            if bsdf and tex_diff:
                # Add a mix node to lighten (Blender 4.5 API)
                mix_node = nodes.new(type='ShaderNodeMix')
                mix_node.data_type = 'RGBA'
                mix_node.blend_type = 'MIX'
                mix_node.location = (-200, 0)
                
                # Set mix factor using index (Blender 4.5)
                mix_node.inputs[0].default_value = 0.3  # Fac = 30% white
                
                # White color
                white = nodes.new(type='ShaderNodeRGB')
                white.location = (-400, -100)
                white.outputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
                
                # Reconnect: texture -> mix -> BSDF
                # Disconnect old link first
                for link in list(mat.node_tree.links):
                    if link.to_node == bsdf and link.to_socket.name == 'Base Color':
                        mat.node_tree.links.remove(link)
                
                mat.node_tree.links.new(tex_diff.outputs['Color'], mix_node.inputs[6])  # Color1
                mat.node_tree.links.new(white.outputs['Color'], mix_node.inputs[7])  # Color2
                mat.node_tree.links.new(mix_node.outputs['Result'], bsdf.inputs['Base Color'])
                print(f"  ✓ Lightened texture by 30%")
        
        backdrop.data.materials.clear()
        backdrop.data.materials.append(mat)
        
        print(f"\n✅ Applied {texture_id} texture")
        
        # Pack images into blend file
        for img in bpy.data.images:
            if texture_id in img.name:
                img.pack()
                print(f"  ✓ Packed {img.name}")
        
        bpy.ops.wm.save_as_mainfile(filepath=backdrop_path)
        print(f"✅ Saved backdrop with Polyhaven texture")
    else:
        print("\n⚠️ Failed to download texture")
else:
    print("✗ Backdrop not found")

