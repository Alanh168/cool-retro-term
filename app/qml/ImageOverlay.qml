/*******************************************************************************
* Image Overlay for cool-retro-term
* Renders sprite PNGs at native resolution on top of the terminal grid.
* Sprite commands arrive via OSC 99 escape sequences from the terminal program.
*
* Command format: \e]99;sprite_id;cell_x;cell_y;target_cell_height\a
*   target_cell_height: how many terminal cells tall the sprite should be
* Clear command:  \e]99;clear\a
*******************************************************************************/

import QtQuick 2.2

Item {
    id: imageOverlay

    // The directory containing sprite PNG files (e.g., agumon.png, monster_wolf.png)
    property string spriteDirectory: ""

    // Font metrics from the terminal, used to convert cell coords to pixel coords
    property real cellWidth: 1.0
    property real cellHeight: 1.0

    // Terminal margin offset
    property real terminalMargin: 0

    // Active sprite commands — list of {spriteId, cellX, cellY, targetCellHeight}
    property var activeSprites: []

    // Process an incoming sprite command string
    function handleSpriteCommand(command) {
        if (command === "clear") {
            activeSprites = [];
            spriteRepeater.model = [];
            return;
        }

        // Parse: "sprite_id;cell_x;cell_y;target_cell_height"
        var parts = command.split(";");
        if (parts.length < 4) {
            console.warn("ImageOverlay: malformed sprite command: " + command);
            return;
        }

        var spriteId = parts[0];
        var cellX = parseInt(parts[1]);
        var cellY = parseInt(parts[2]);
        var targetCellHeight = parseFloat(parts[3]);

        if (isNaN(cellX) || isNaN(cellY) || isNaN(targetCellHeight) || targetCellHeight <= 0) {
            console.warn("ImageOverlay: invalid values in command: " + command);
            return;
        }

        // Replace any existing sprite at the same position, or add new
        var sprites = activeSprites.slice(); // copy
        var found = false;
        for (var i = 0; i < sprites.length; i++) {
            if (sprites[i].cellX === cellX && sprites[i].cellY === cellY) {
                sprites[i] = { spriteId: spriteId, cellX: cellX, cellY: cellY, targetCellHeight: targetCellHeight };
                found = true;
                break;
            }
        }
        if (!found) {
            sprites.push({ spriteId: spriteId, cellX: cellX, cellY: cellY, targetCellHeight: targetCellHeight });
        }

        activeSprites = sprites;
        spriteRepeater.model = sprites;
    }

    Repeater {
        id: spriteRepeater
        model: []

        Image {
            property var spriteData: modelData

            // Target pixel height based on cell height
            property real targetHeight: spriteData.targetCellHeight * cellHeight

            // Convert sprite_ref to filename: underscores become hyphens, append .png
            source: spriteDirectory + "/" + spriteData.spriteId.replace(/_/g, "-") + ".png"

            // Size: fit to target cell height, preserve aspect ratio
            height: targetHeight
            width: (sourceSize.width > 0 && sourceSize.height > 0)
                   ? sourceSize.width * (targetHeight / sourceSize.height)
                   : targetHeight

            // Position: right edge aligns with cellX, vertically centered on the row.
            x: spriteData.cellX * cellWidth + terminalMargin - width
            y: spriteData.cellY * cellHeight + terminalMargin - (targetHeight - cellHeight) / 2

            fillMode: Image.PreserveAspectFit
            smooth: false  // Keep pixel art crisp
            visible: status === Image.Ready

            onStatusChanged: {
                if (status === Image.Error) {
                    // Try alternate naming: without hyphen conversion
                    source = spriteDirectory + "/" + spriteData.spriteId + ".png";
                }
            }
        }
    }
}
