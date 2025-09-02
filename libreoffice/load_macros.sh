#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────── args / sanity ──────────────────────────────
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/YourMacro.py" >&2
  exit 1
fi

MACRO_SRC="$(realpath "$1")"
if [[ ! -f "$MACRO_SRC" ]]; then
  echo "Error: file not found – $MACRO_SRC" >&2
  exit 1
fi
MACRO_FILE="$(basename "$MACRO_SRC")"        # e.g. MakeTable.py
MACRO_NAME="${MACRO_FILE%.*}"                 # e.g. MakeTable (without .py)
EXT_NAME="${MACRO_NAME}Extension"             # e.g. MakeTableExtension

# adjust if LibreOffice lives elsewhere:
LIBO_APP="/Applications/LibreOffice.app/Contents/MacOS"

# ───────────────────────────── build tree ──────────────────────────────────
rm -rf   "$EXT_NAME"
mkdir -p "$EXT_NAME/Scripts/python"

cp "$MACRO_SRC" "$EXT_NAME/Scripts/python/"

# ── description.xml ────────────────────────────────────────────────────────
cat > "$EXT_NAME/description.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<description xmlns="http://openoffice.org/extensions/description/2006">
  <identifier value="org.example.$(echo "$MACRO_NAME" | tr '[:upper:]' '[:lower:]')"/>
  <version value="1.0"/>
  <display-name><name xml:lang="en">${MACRO_NAME}</name></display-name>
  <extension-description>
    <src xml:lang="en">Custom macro: ${MACRO_NAME}</src>
  </extension-description>
</description>
XML

# ── Addons.xcu (toolbar definition) ────────────────────────────────────────
cat > "$EXT_NAME/Addons.xcu" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<oor:component-data oor:name="Addons" oor:package="org.openoffice.Office"
  xmlns:oor="http://openoffice.org/2001/registry">
  <node oor:name="Addon">
    <node oor:name="${MACRO_NAME}Addon">
      <node oor:name="OfficeToolBar">
        <node oor:name="${MACRO_NAME}Bar" oor:op="replace">
          <prop oor:name="Title" oor:type="xs:string">
            <value xml:lang="en">${MACRO_NAME}</value>
          </prop>
          <node oor:name="Items">
            <node oor:name="cmd1" oor:op="replace">
              <prop oor:name="CommandURL" oor:type="xs:string">
                <value>
vnd.sun.star.script:${MACRO_FILE}\$main?language=Python&amp;location=user
                </value>
              </prop>
              <prop oor:name="Title" oor:type="xs:string">
                <value xml:lang="en">Run ${MACRO_NAME}</value>
              </prop>
              <prop oor:name="Type" oor:type="xs:int"><value>0</value></prop>
            </node>
          </node>
        </node>
      </node>
    </node>
  </node>
</oor:component-data>
XML

# ── package & install ──────────────────────────────────────────────────────
zip -rq "${EXT_NAME}.oxt" "$EXT_NAME"

# Check if extension is already installed and remove it first
if "${LIBO_APP}/unopkg" list | grep -q "${EXT_NAME}.oxt"; then
  echo "⚠️ Extension ${EXT_NAME}.oxt is already installed. Removing it first..."
  "${LIBO_APP}/unopkg" remove "${EXT_NAME}.oxt" || true
fi

"${LIBO_APP}/unopkg" add "${EXT_NAME}.oxt"

echo "✓ ${MACRO_NAME} extension installed. Restart LibreOffice Calc ⇒ toolbar appears."
