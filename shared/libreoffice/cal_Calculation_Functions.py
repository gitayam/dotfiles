# -*- coding: utf-8 -*-
"""
CalcMacros.py

Eight handy Python/UNO macros for LibreOffice Calc:
  1. convert_formulas_to_values
  2. highlight_duplicates_in_selection
  3. strip_whitespace_in_selection
  4. insert_timestamp
  5. remove_empty_rows
  6. add_totals_row
  7. export_sheet_as_csv
  8. consolidate_all_sheets

Place this file in:
  ~/.config/libreoffice/4/user/Scripts/python/CalcMacros.py
or
  ~/Library/Application Support/LibreOffice/4/user/Scripts/python/CalcMacros.py
then restart Calc and bind each function under My Macros ▸ CalcMacros.
"""

import uno, os, re
from datetime import datetime
from com.sun.star.awt.FontWeight import BOLD
from com.sun.star.beans import PropertyValue

# ─── Helpers ────────────────────────────────────────────────────────────────
def _uno_service(name):
    ctx  = XSCRIPTCONTEXT.getComponentContext()
    smgr = ctx.ServiceManager
    return smgr.createInstanceWithContext(name, ctx)

def _msgbox(msg, title="Calc Macro"):
    frame   = XSCRIPTCONTEXT.getDocument().CurrentController.Frame
    window  = frame.ContainerWindow
    toolkit = window.getToolkit()
    rect    = uno.createUnoStruct("com.sun.star.awt.Rectangle")
    try:
        box = toolkit.createMessageBox(window, rect, "infobox", 1, title, msg)
    except TypeError:
        box = toolkit.createMessageBox(rect, "infobox", 1, title, msg)
    box.execute()

def _col_to_letter(col):
    """Convert zero-based col index to A, B, ..., Z, AA, AB, ..."""
    s = ""
    while True:
        s = chr(ord('A') + (col % 26)) + s
        col = col // 26 - 1
        if col < 0:
            break
    return s

# ─── 1. Convert Formulas to Values ──────────────────────────────────────────
def convert_formulas_to_values():
    doc = XSCRIPTCONTEXT.getDocument()
    sel = doc.getCurrentSelection()
    if not sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        _msgbox("Select a range first.")
        return
    rows = sel.Rows.getCount()
    cols = sel.Columns.getCount()
    addr = sel.RangeAddress
    sheet = sel.Spreadsheet
    for r in range(addr.StartRow, addr.StartRow+rows):
        for c in range(addr.StartColumn, addr.StartColumn+cols):
            cell = sheet.getCellByPosition(c, r)
            if cell.Formula:
                val = cell.Value
                cell.Formula = ""
                cell.Value = val
    _msgbox("Formulas have been replaced with their values.")

# ─── 2. Highlight Duplicates ────────────────────────────────────────────────
def highlight_duplicates_in_selection():
    doc = XSCRIPTCONTEXT.getDocument()
    sel = doc.getCurrentSelection()
    if not sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        _msgbox("Select a range first.")
        return
    addr = sel.RangeAddress
    sheet = sel.Spreadsheet

    # build frequency map
    freq = {}
    for r in range(addr.StartRow, addr.EndRow+1):
        for c in range(addr.StartColumn, addr.EndColumn+1):
            cell = sheet.getCellByPosition(c, r)
            key = cell.String if cell.Type == 1 else str(cell.Value)
            if key != "":
                freq[key] = freq.get(key, 0) + 1

    # highlight any with freq > 1
    HIGHLIGHT = 0xFFFF66  # pale yellow
    for r in range(addr.StartRow, addr.EndRow+1):
        for c in range(addr.StartColumn, addr.EndColumn+1):
            cell = sheet.getCellByPosition(c, r)
            key = cell.String if cell.Type == 1 else str(cell.Value)
            if freq.get(key, 0) > 1:
                cell.CellBackColor = HIGHLIGHT

    _msgbox("Duplicate values have been highlighted.")

# ─── 3. Strip Whitespace / Clean Text ───────────────────────────────────────
def strip_whitespace_in_selection():
    doc = XSCRIPTCONTEXT.getDocument()
    sel = doc.getCurrentSelection()
    if not sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        _msgbox("Select a range first.")
        return
    addr = sel.RangeAddress
    sheet = sel.Spreadsheet
    for r in range(addr.StartRow, addr.EndRow+1):
        for c in range(addr.StartColumn, addr.EndColumn+1):
            cell = sheet.getCellByPosition(c, r)
            if cell.Type == 1 and cell.String:
                cleaned = re.sub(r"\s+", " ", cell.String.strip())
                cell.String = cleaned
    _msgbox("Whitespace trimmed and collapsed.")

# ─── 4. Insert Timestamp ───────────────────────────────────────────────────
def insert_timestamp():
    doc = XSCRIPTCONTEXT.getDocument()
    sel = doc.getCurrentSelection()
    if not sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        _msgbox("Select a range first.")
        return
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    addr = sel.RangeAddress
    sheet = sel.Spreadsheet
    for r in range(addr.StartRow, addr.EndRow+1):
        for c in range(addr.StartColumn, addr.EndColumn+1):
            cell = sheet.getCellByPosition(c, r)
            cell.String = now
    _msgbox("Current timestamp inserted in selection.")

# ─── 5. Remove Empty Rows ──────────────────────────────────────────────────
def remove_empty_rows():
    doc = XSCRIPTCONTEXT.getDocument()
    sel = doc.getCurrentSelection()
    if not sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        _msgbox("Select a range first.")
        return
    addr = sel.RangeAddress
    sheet = sel.Spreadsheet
    # bottom→top to avoid reindexing issues
    for r in range(addr.EndRow, addr.StartRow-1, -1):
        empty = True
        for c in range(addr.StartColumn, addr.EndColumn+1):
            cell = sheet.getCellByPosition(c, r)
            if (cell.Type == 1 and cell.String != "") or (cell.Type != 1 and cell.Value != 0):
                empty = False
                break
        if empty:
            sheet.Rows.removeByIndex(r, 1)
    _msgbox("Empty rows removed from selection.")

# ─── 6. Add Totals Row ─────────────────────────────────────────────────────
def add_totals_row():
    doc = XSCRIPTCONTEXT.getDocument()
    sel = doc.getCurrentSelection()
    if not sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        _msgbox("Select a range first.")
        return
    addr = sel.RangeAddress
    sheet = sel.Spreadsheet
    total_idx = addr.EndRow + 1
    # insert a blank row for totals
    sheet.Rows.insertByIndex(total_idx, 1)
    for c in range(addr.StartColumn, addr.EndColumn+1):
        col = _col_to_letter(c)
        start = addr.StartRow + 1
        end   = addr.EndRow + 1
        cell = sheet.getCellByPosition(c, total_idx)
        cell.FormulaLocal = "=SUM(%s%d:%s%d)" % (col, start, col, end)
    _msgbox("Totals row added below the selection.")

# ─── 7. Export Sheet as CSV ────────────────────────────────────────────────
def export_sheet_as_csv():
    doc = XSCRIPTCONTEXT.getDocument()
    sheet = doc.getCurrentController().getActiveSheet()
    name  = sheet.getName() + ".csv"
    home  = os.path.expanduser("~")
    path  = os.path.join(home, "Desktop", name)
    url   = uno.systemPathToFileUrl(path)

    # prepare filter properties
    props = []
    p = PropertyValue()
    p.Name  = "FilterName"
    p.Value = "Text - txt - csv (StarCalc)"
    props.append(p)

    doc.storeToURL(url, tuple(props))
    _msgbox(f"Sheet exported to CSV:\n{path}")

# ─── 8. Consolidate All Sheets ─────────────────────────────────────────────
def consolidate_all_sheets():
    doc    = XSCRIPTCONTEXT.getDocument()
    sheets = doc.getSheets()
    # create or clear "Master"
    if sheets.hasByName("Master"):
        master = sheets.getByName("Master")
        master.clearContents(1023)
    else:
        master = sheets.insertNewByName("Master", 0)

    dest_row = 0
    for name in sheets.getElementNames():
        if name == master.getName(): 
            continue
        s = sheets.getByName(name)
        cursor = s.createCursor()
        cursor.gotoEndOfUsedArea(True)
        ea = cursor.getRangeAddress()
        rows = ea.EndRow + 1
        cols = ea.EndColumn + 1
        src = s.getCellRangeByPosition(0, 0, cols-1, rows-1).getDataArray()
        dest = master.getCellRangeByPosition(0, dest_row, cols-1, dest_row+rows-1)
        dest.setDataArray(src)
        dest_row += rows

    _msgbox(f"All sheets consolidated into '{master.getName()}'.")
    

# LibreOffice entry points
g_exportedScripts = (
    convert_formulas_to_values,
    highlight_duplicates_in_selection,
    strip_whitespace_in_selection,
    insert_timestamp,
    remove_empty_rows,
    add_totals_row,
    export_sheet_as_csv,
    consolidate_all_sheets,
)
