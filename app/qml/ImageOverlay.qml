/*******************************************************************************
* Image Overlay for cool-retro-term
* Renders sprite PNGs at native resolution on top of the terminal grid.
* Sprite commands arrive via OSC 99 escape sequences from the terminal program.
*
* Command format: \e]99;sprite_id;cell_x;cell_y;target_cell_height[;target_cell_width;anchor]\a
*   target_cell_height: how many terminal cells tall the sprite may be
*   target_cell_width: optional max width in terminal cells
*   anchor: optional horizontal anchor ("right" or "center")
* Clear command:  \e]99;clear\a
*******************************************************************************/

import QtQuick 2.2

Rectangle {
    id: imageOverlay
    color: "transparent"

    // The directory containing sprite PNG files (e.g., agumon.png, monster_wolf.png)
    property string spriteDirectory: ""

    // Font metrics from the terminal, used to convert cell coords to pixel coords
    property real cellWidth: 1.0
    property real cellHeight: 1.0

    // Terminal margin offset
    property real terminalMargin: 0

    // Active sprite commands — list of
    // {spriteId, cellX, cellY, targetCellHeight, targetCellWidth, anchor}
    property var activeSprites: []
    property int clearGeneration: 0

    function clearSprites() {
        clearGeneration += 1;

        for (var i = 0; i < spriteRepeater.count; i += 1) {
            var item = spriteRepeater.itemAt(i);
            if (item) {
                item.source = "";
                item.sourceCandidates = [];
            }
        }

        activeSprites = [];
        spriteRepeater.model = [];
    }

    function parseFrameSprites(payload, generation) {
        var sprites = [];
        if (!payload)
            return sprites;

        var entries = payload.split("|");
        for (var i = 0; i < entries.length; i += 1) {
            var entry = entries[i];
            if (!entry)
                continue;

            var parts = entry.split(",");
            if (parts.length < 4)
                continue;

            var spriteId = parts[0];
            var cellX = parseFloat(parts[1]);
            var cellY = parseFloat(parts[2]);
            var targetCellHeight = parseFloat(parts[3]);
            var targetCellWidth = (parts.length > 4 && parts[4] !== "")
                ? parseFloat(parts[4])
                : 0;
            var anchor = parts.length > 5 ? parts[5] : "right";
            if (anchor !== "center")
                anchor = "right";

            if (spriteId && !isNaN(cellX) && !isNaN(cellY)
                && !isNaN(targetCellHeight) && targetCellHeight > 0) {
                sprites.push({
                    spriteId: spriteId,
                    cellX: cellX,
                    cellY: cellY,
                    targetCellHeight: targetCellHeight,
                    targetCellWidth: (!isNaN(targetCellWidth) && targetCellWidth > 0)
                        ? targetCellWidth
                        : 0,
                    anchor: anchor,
                    generation: generation
                });
            }
        }

        return sprites;
    }

    // Process an incoming sprite command string
    function handleSpriteCommand(command) {
        var normalizedCommand = (command || "").trim();
        if (normalizedCommand === "clear") {
            clearSprites();
            return;
        }

        if (normalizedCommand.indexOf("frame;") === 0) {
            var frameParts = normalizedCommand.split(";");
            if (frameParts.length < 2) {
                console.warn("ImageOverlay: malformed frame command: " + normalizedCommand);
                return;
            }

            var generation = parseInt(frameParts[1], 10);
            if (isNaN(generation)) {
                console.warn("ImageOverlay: invalid frame generation: " + normalizedCommand);
                return;
            }
            if (generation < clearGeneration)
                return;

            var payload = frameParts.length > 2 ? frameParts.slice(2).join(";") : "";
            var frameSprites = parseFrameSprites(payload, generation);
            clearGeneration = generation;
            activeSprites = frameSprites;
            spriteRepeater.model = frameSprites;
            return;
        }

        // Parse: "sprite_id;cell_x;cell_y;target_cell_height[;target_cell_width;anchor]"
        var parts = normalizedCommand.split(";");
        if (parts.length < 4) {
            console.warn("ImageOverlay: malformed sprite command: " + normalizedCommand);
            return;
        }

        var spriteId = parts[0];
        var cellX = parseFloat(parts[1]);
        var cellY = parseFloat(parts[2]);
        var targetCellHeight = parseFloat(parts[3]);
        var targetCellWidth = (parts.length > 4 && parts[4] !== "")
            ? parseFloat(parts[4])
            : 0;
        var anchor = parts.length > 5 ? parts[5] : "right";
        if (anchor !== "center")
            anchor = "right";

        if (isNaN(cellX) || isNaN(cellY) || isNaN(targetCellHeight) || targetCellHeight <= 0) {
            console.warn("ImageOverlay: invalid values in command: " + normalizedCommand);
            return;
        }

        var sprite = {
            spriteId: spriteId,
            cellX: cellX,
            cellY: cellY,
            targetCellHeight: targetCellHeight,
            targetCellWidth: (!isNaN(targetCellWidth) && targetCellWidth > 0)
                ? targetCellWidth
                : 0,
            anchor: anchor,
            generation: clearGeneration
        };
        var nextSprites = activeSprites.slice(0);
        nextSprites.push(sprite);
        activeSprites = nextSprites;
        spriteRepeater.model = nextSprites;
    }

    Repeater {
        id: spriteRepeater
        model: []

        Image {
            property var spriteData: modelData
            property var sourceCandidates: []
            property int sourceIndex: 0

            function buildSourceCandidates(spriteId) {
                var candidates = [];
                var normalizedId = spriteId.replace(/_/g, "-");

                candidates.push(spriteDirectory + "/" + normalizedId + ".png");

                if (normalizedId !== spriteId) {
                    candidates.push(spriteDirectory + "/" + spriteId + ".png");
                }

                if (spriteId.indexOf("/") === -1) {
                    candidates.push(spriteDirectory + "/official/" + normalizedId + ".png");
                    if (normalizedId !== spriteId) {
                        candidates.push(spriteDirectory + "/official/" + spriteId + ".png");
                    }
                }

                return candidates;
            }

            function resetSource() {
                sourceCandidates = buildSourceCandidates(spriteData.spriteId);
                sourceIndex = 0;
                source = sourceCandidates.length > 0 ? sourceCandidates[0] : "";
            }

            // Target pixel height based on cell height
            property real targetHeight: spriteData.targetCellHeight * cellHeight
            property bool hasWidthConstraint: spriteData.targetCellWidth > 0
            property real targetWidth: hasWidthConstraint
                ? spriteData.targetCellWidth * cellWidth
                : 0
            property real fittedScale: (sourceSize.width > 0 && sourceSize.height > 0)
                ? Math.min(targetWidth / sourceSize.width, targetHeight / sourceSize.height)
                : 0

            source: ""

            // Size: preserve aspect ratio, optionally fit within a bounding box.
            height: hasWidthConstraint
                ? ((sourceSize.width > 0 && sourceSize.height > 0)
                    ? sourceSize.height * fittedScale
                    : 0)
                : targetHeight
            width: hasWidthConstraint
                ? ((sourceSize.width > 0 && sourceSize.height > 0)
                    ? sourceSize.width * fittedScale
                    : 0)
                : ((sourceSize.width > 0 && sourceSize.height > 0)
                    ? sourceSize.width * (targetHeight / sourceSize.height)
                    : targetHeight)

            // Position: right-aligned by default, or centered when requested.
            x: spriteData.anchor === "center"
                ? spriteData.cellX * cellWidth + terminalMargin - (width / 2)
                : spriteData.cellX * cellWidth + terminalMargin - width
            y: spriteData.cellY * cellHeight + terminalMargin - (height - cellHeight) / 2

            fillMode: Image.PreserveAspectFit
            smooth: false  // Keep pixel art crisp
            visible: status === Image.Ready && spriteData.generation === imageOverlay.clearGeneration

            Component.onCompleted: resetSource()
            onSpriteDataChanged: resetSource()

            onStatusChanged: {
                if (status === Image.Error && sourceIndex + 1 < sourceCandidates.length) {
                    sourceIndex += 1;
                    source = sourceCandidates[sourceIndex];
                }
            }
        }
    }
}
