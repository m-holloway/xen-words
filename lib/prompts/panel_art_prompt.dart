/// System prompt for generating panel art grid from panel descriptions.
/// 
/// This prompt instructs the image generation model to create a 1024x1024
/// grid of story panels arranged in a 4-column layout.
const String panelArtPrompt = '''
You are generating a single high-resolution comic page image.  
Follow ALL instructions below EXACTLY and WITHOUT EXCEPTION.

====================================================================
GOAL
Create a 1024×1024 px comic page containing EXACTLY [N] illustrated 
story panels, arranged inside a strict 4-column grid.  
The grid is ALWAYS 4 rows by 4 columns (16 total square cells).  
Any cells not used for illustrated panels MUST be filled with blank
white squares.

THIS IS A **WORDLESS ILLUSTRATION** PAGE:
- Absolutely NO written text anywhere in the image.
- NO speech bubbles, chat balloons, or thought bubbles.
- NO sound effects (\"BANG\", \"WHOOSH\", \"POW\", etc.).
- NO labels, captions, UI elements, logos, or typography of any kind.
====================================================================

====================================================================
GRID LAYOUT (STRICT, MATHEMATICAL, NON-NEGOTIABLE)
You MUST place each illustrated panel k (starting at 1) using this formula:

    row_index r = floor((k - 1) / 4)
    column_index c = (k - 1) mod 4

This creates a 4-column layout:
Panel 1  → row 0, col 0  
Panel 2  → row 0, col 1  
Panel 3  → row 0, col 2  
Panel 4  → row 0, col 3  
Panel 5  → row 1, col 0  
Panel 6  → row 1, col 1  
…continue sequentially through Panel [N].

- NO reordering.  
- NO centering.  
- NO shifting for aesthetic reasons.  
- NO creative reinterpretation of panel positions.  
This layout is mechanical and MUST be followed precisely.

Number of rows:  
Let R = 4.  
You MUST generate exactly 4 rows and exactly 4 columns per row  
for a total of 16 square cells, regardless of [N].  
Never change the number of rows or columns based on [N].
====================================================================

====================================================================
UNUSED CELLS RULE (CRITICAL)
There are ALWAYS 16 cells in the grid (4 rows × 4 columns).  
You will receive [N] panel descriptions. Let K = min([N], 16).

1. You MUST create illustrated panels for **exactly K** panels:
   - Use Panel 1 for cell (row 0, col 0)
   - Panel 2 for (row 0, col 1)
   - Panel 3 for (row 0, col 2)
   - Panel 4 for (row 0, col 3)
   - Panel 5 for (row 1, col 0)
   - …continue in strict reading order until Panel K.

2. ALL remaining cells from K+1 up to 16 MUST be filled with **blank white squares**, 
   and MUST use the remaining cells in reading order (left to right, top to bottom).

Blank white squares are defined as:
- pure white (#FFFFFF)
- no shading, texture, gradients, symbols, or decoration
- identical in size to the illustrated panels

Under NO circumstances may the model:
- center the last row's illustrated panels  
- shift illustrated panels into the middle  
- add art to blank squares  
- modify the grid structure  
====================================================================

====================================================================
GRID & GUTTER REQUIREMENTS
1. All cells (illustrated panels + blank squares) MUST be perfect squares.
2. Every square MUST be identical in size.
3. The complete grid MUST fill the entire 1024×1024 px canvas.
4. The size and number of cells (4×4, 16 total) MUST NEVER change,
   no matter how many panels [N] you are asked to render.
5. Gutters MUST be:
   - thin
   - clean
   - solid black (#000000)
   - uniform width between all cells

Absolutely NO artwork may spill across gutters.
====================================================================

====================================================================
RENDERING ORDER (MANDATORY)
You MUST perform the following steps IN ORDER:

1. Construct the entire empty grid of R rows × 4 columns.
2. Fill the illustrated panels IN NUMERICAL ORDER:
   Panel 1 → Panel 2 → Panel 3 → … → Panel [N].
3. After all illustrated panels are filled,  
   insert blank white squares into any remaining rightmost cells.
4. Do NOT fill illustrated panels out of order.
5. Do NOT add imagery to blank squares.
====================================================================

====================================================================
ART STYLE
[ART_STYLE_DESCRIPTION]

Apply this style consistently to EVERY illustrated panel.
====================================================================

====================================================================
CONTENT RENDERING (STRICT)
- Render ONLY what is described in each panel's brief.  
- DO NOT add any text or writing anywhere in the image.  
- NO speech bubbles, thought bubbles, or chat balloons.  
- NO sound effect words (\"BANG\", \"WHOOSH\", \"POW\", etc.).  
- NO labels, captions, signs with readable text, UI, or logos.  
- If the story implies dialogue, show it ONLY through character poses,
  facial expressions, and body language—NEVER as written words.  
- DO NOT display panel numbers.  
- DO NOT introduce new elements not present in the panel descriptions.  
- DO NOT reinterpret or embellish beyond what the panel description specifies.  
====================================================================

====================================================================
PANEL CONTENT (RENDER LITERALLY)
Paste the list of panel descriptions here:

[PANEL_LIST]
====================================================================

OUTPUT
Produce a single 1024×1024 px image containing:
- 4 × 4 square grid cells (16 total)  
- Illustrated panels placed based on the mathematical formula  
- Blank white squares in all unused cells after the last illustrated panel  
- Perfectly aligned grid with clean black gutters  
- A layout that can be programmatically sliced with simple pixel math
''';

