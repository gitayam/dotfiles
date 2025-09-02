# -*- coding: utf-8 -*-
# make_table_from_selection.py  (macOS-safe, with fallback styling)
#
# One-click “Format as Table” for LibreOffice Calc:
#   • turns current selection into a database range called QuickTable
#   • adds AutoFilter ▼ arrows
#   • tries the built-in “Blue” TableAutoFormat (index 13)
#   • if unavailable, applies home-made blue stripes + bold header
#   • freezes the header row

import uno
from com.sun.star.awt.FontWeight import BOLD

# -------------------------------------------------------------------- helpers
def _uno_service(name: str):
    """Portable replacement for uno.createUnoService()."""
    ctx  = XSCRIPTCONTEXT.getComponentContext()
    smgr = ctx.ServiceManager
    try:
        return smgr.createInstanceWithContext(name, ctx)
    except Exception:
        return None  # service not found on this build

def _msgbox(msg: str, title: str = "Quick Table"):
    frame   = XSCRIPTCONTEXT.getDocument().CurrentController.Frame
    window  = frame.ContainerWindow
    toolkit = window.getToolkit()
    rect    = uno.createUnoStruct("com.sun.star.awt.Rectangle")
    try:
        box = toolkit.createMessageBox(window, rect, "infobox", 1, title, msg)
    except TypeError:                 # macOS 5-arg signature
        box = toolkit.createMessageBox(rect, "infobox", 1, title, msg)
    box.execute()

def _hex(color_hex):
    """Convert HTML-style 0xRRGGBB (or '#RRGGBB') to LibreOffice int."""
    if isinstance(color_hex, str):
        color_hex = color_hex.lstrip("#")
        return int(color_hex, 16)
    return color_hex

# -------------------------------------------------------------------- fallback styling
def _apply_manual_banding(sel, addr, header_rgb="#D6E5F3", band_rgb="#EAF1FB"):
    sheet     = sel.Spreadsheet
    start_row = addr.StartRow
    end_row   = addr.EndRow
    start_col = addr.StartColumn
    end_col   = addr.EndColumn

    # Header style
    header = sheet.getCellRangeByPosition(start_col, start_row,
                                          end_col,   start_row)
    header.CharWeight = BOLD
    header.CellBackColor = _hex(header_rgb)

    # Banded rows  (every second data row starting with first data row)
    for r in range(start_row + 1, end_row + 1, 2):
        band = sheet.getCellRangeByPosition(start_col, r, end_col, r)
        band.CellBackColor = _hex(band_rgb)

# -------------------------------------------------------------------- main macro
def make_table_from_selection():
    doc = XSCRIPTCONTEXT.getDocument()
    sel = doc.getCurrentSelection()

    # 1. Validation ----------------------------------------------------------
    if not sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        _msgbox("Select a contiguous rectangle of cells first.")
        return
    if sel.Rows.getCount() < 2:
        _msgbox("Need at least a header row and one data row.")
        return

    addr = sel.RangeAddress  # struct copy

    # 2. Database range ------------------------------------------------------
    db_ranges = doc.DatabaseRanges
    name      = "QuickTable"
    if db_ranges.hasByName(name):
        db_range = db_ranges.getByName(name)
        db_range.setDataArea(addr)          # reuse for new selection
    else:
        db_ranges.addNewByName(name, addr)
        db_range = db_ranges.getByName(name)

    # 3. AutoFilter ----------------------------------------------------------
    db_range.AutoFilter = True

    # 4. Try built-in AutoFormat --------------------------------------------
    auto_fmt = _uno_service("com.sun.star.sheet.TableAutoFormat")
    if auto_fmt:
        try:
            auto_fmt.applyAutoFormat(
                sel,
                13,                       # “Blue” banded rows
                True, True, True, True, True, True
            )
        except Exception:
            auto_fmt = None  # fall back if call fails

    # 5. Fallback banding if AutoFormat missing -----------------------------
    if auto_fmt is None:
        _apply_manual_banding(sel, addr)

    # -- 6. Freeze ONLY the top row, never the left column ----------------------
    controller = doc.getCurrentController()
    controller.unfreeze()            # clear any existing freeze/split
    controller.freezeAtPosition(0, 1)  # x=0 (no column freeze), y=1 (freeze row 1)

# LibreOffice registers any functions listed here as macros
g_exportedScripts = (make_table_from_selection,)