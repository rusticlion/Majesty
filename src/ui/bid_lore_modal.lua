-- bid_lore_modal.lua
-- Challenge-phase Bid Lore modal UI and submission flow.

local events = require('logic.events')

local M = {}

M.COLORS = {
    backdrop = { 0.03, 0.03, 0.04, 0.72 },
    panel_bg = { 0.12, 0.10, 0.08, 0.97 },
    panel_border = { 0.54, 0.48, 0.38, 1.0 },
    title = { 0.94, 0.90, 0.80, 1.0 },
    text = { 0.82, 0.79, 0.72, 1.0 },
    dim_text = { 0.62, 0.60, 0.54, 1.0 },
    section_bg = { 0.16, 0.14, 0.11, 1.0 },
    section_border = { 0.44, 0.40, 0.34, 1.0 },
    section_active = { 0.72, 0.63, 0.38, 1.0 },
    row_bg = { 0.20, 0.17, 0.14, 1.0 },
    row_selected = { 0.34, 0.28, 0.19, 1.0 },
    row_hover = { 0.30, 0.24, 0.17, 1.0 },
    button_bg = { 0.24, 0.20, 0.16, 1.0 },
    button_hover = { 0.36, 0.30, 0.22, 1.0 },
    button_border = { 0.55, 0.50, 0.42, 1.0 },
    button_primary = { 0.66, 0.56, 0.30, 1.0 },
    warn = { 0.88, 0.45, 0.40, 1.0 },
}

M.WIDTH = 860
M.HEIGHT = 560

local FIELD_ORDER = { "npc", "subject", "question", "motif", "focus" }
local FIELD_INDEX = {
    npc = 1,
    subject = 2,
    question = 3,
    motif = 4,
    focus = 5,
}

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function listContains(items, value)
    for _, item in ipairs(items or {}) do
        if item == value then
            return true
        end
    end
    return false
end

local function optionLabel(field, option)
    if field == "npc" then
        return option.name or option.id or "Room Context"
    end
    if field == "subject" then
        local kind = option.kind or "subject"
        return string.format("%s [%s]", option.name or option.id or "Subject", kind)
    end
    if field == "question" then
        return option.name or option.id or "Question"
    end
    if field == "motif" then
        return tostring(option)
    end
    if field == "focus" then
        return tostring(option)
    end
    return tostring(option)
end

function M.createBidLoreModal(config)
    config = config or {}

    local modal = {
        eventBus = config.eventBus or events.globalBus,
        engine = config.engine,

        isVisible = false,
        x = 0,
        y = 0,
        width = M.WIDTH,
        height = M.HEIGHT,

        actor = nil,
        pendingAction = nil,
        challengeController = nil,
        roomId = nil,

        encounterNPCs = {
            {
                id = "__room_context",
                name = "Room Context (no NPC filter)",
                isRoomContext = true,
            },
        },
        allSubjects = {},
        subjects = {},
        questions = {},
        motifs = {},
        focusTokens = { "(none)" },
        npcFilterFallback = false,

        selected = {
            npc = 1,
            subject = 1,
            question = 1,
            motif = 1,
            focus = 1,
        },
        activeField = 1,

        optionBounds = {},
        submitButtonBounds = nil,
        cancelButtonBounds = nil,
        hoveredOption = nil,
        hoveredButton = nil,
        colors = M.COLORS,
    }

    function modal:init()
        self.eventBus:on(events.EVENTS.REQUEST_BID_LORE, function(data)
            self:start(data)
        end)
    end

    function modal:hide()
        self.isVisible = false
        self.actor = nil
        self.pendingAction = nil
        self.challengeController = nil
        self.roomId = nil
        self.encounterNPCs = {
            {
                id = "__room_context",
                name = "Room Context (no NPC filter)",
                isRoomContext = true,
            },
        }
        self.allSubjects = {}
        self.subjects = {}
        self.questions = {}
        self.motifs = {}
        self.focusTokens = { "(none)" }
        self.npcFilterFallback = false
        self.optionBounds = {}
        self.submitButtonBounds = nil
        self.cancelButtonBounds = nil
        self.hoveredOption = nil
        self.hoveredButton = nil
    end

    function modal:buildEncounterNPCs()
        local encounterNPCs = {
            {
                id = "__room_context",
                name = "Room Context (no NPC filter)",
                isRoomContext = true,
            },
        }

        for index, npc in ipairs(self.challengeController and self.challengeController.npcs or {}) do
            if not (npc.conditions and npc.conditions.dead) then
                local baseName = npc.name or npc.blueprintId or ("NPC " .. tostring(index))
                local label = baseName
                if npc.blueprintId then
                    label = string.format("%s [%s]", baseName, npc.blueprintId)
                end

                encounterNPCs[#encounterNPCs + 1] = {
                    id = npc.id or ("npc_" .. tostring(index)),
                    name = label,
                    blueprintId = npc.blueprintId,
                    entity = npc,
                }
            end
        end

        self.encounterNPCs = encounterNPCs
    end

    function modal:start(data)
        if not self.engine then
            return
        end

        data = data or {}
        self.actor = data.actor or data.entity
        self.pendingAction = data.action
        self.challengeController = data.challengeController
        self.roomId = data.roomId or (self.challengeController and self.challengeController.roomId)

        self.allSubjects = data.availableSubjects or {}
        if #self.allSubjects == 0 then
            self.allSubjects = self.engine:getAvailableSubjects({
                actor = self.actor,
                challengeController = self.challengeController,
                roomId = self.roomId,
                action = self.pendingAction,
            })
        end

        self:buildEncounterNPCs()

        self.motifs = self.engine:getActorMotifs(self.actor)
        if #self.motifs == 0 then
            self.motifs = { "(no motifs available)" }
        end

        self.selected.npc = (#self.encounterNPCs > 1) and 2 or 1
        self.selected.subject = 1
        self.selected.question = 1
        self.selected.motif = 1
        self.selected.focus = 1
        self.activeField = FIELD_INDEX.npc

        self:refreshSubjectsQuestionAndFocus()

        local sw, sh = love.graphics.getDimensions()
        self.width = math.min(M.WIDTH, sw - 40)
        self.height = math.min(M.HEIGHT, sh - 40)
        self.x = math.floor((sw - self.width) / 2)
        self.y = math.floor((sh - self.height) / 2)

        self.isVisible = true
    end

    function modal:getSelectedEncounterNPC()
        return self.encounterNPCs[self.selected.npc]
    end

    function modal:getSelectedSubject()
        return self.subjects[self.selected.subject]
    end

    function modal:getSelectedQuestion()
        return self.questions[self.selected.question]
    end

    function modal:getSelectedMotif()
        return self.motifs[self.selected.motif]
    end

    function modal:getSelectedFocus()
        local focus = self.focusTokens[self.selected.focus]
        if focus == "(none)" then
            return nil
        end
        return focus
    end

    function modal:refreshSubjectsQuestionAndFocus()
        local selectedNPC = self:getSelectedEncounterNPC()
        local filteredSubjects = {}

        self.npcFilterFallback = false

        if selectedNPC and not selectedNPC.isRoomContext and selectedNPC.blueprintId then
            for _, subject in ipairs(self.allSubjects or {}) do
                local authored = self.engine:getSubject(subject.id)
                local enemyBlueprintIds = authored and authored.enemyBlueprintIds or subject.enemyBlueprintIds
                if listContains(enemyBlueprintIds, selectedNPC.blueprintId) then
                    filteredSubjects[#filteredSubjects + 1] = subject
                end
            end

            if #filteredSubjects == 0 then
                filteredSubjects = self.allSubjects
                self.npcFilterFallback = true
            end
        else
            filteredSubjects = self.allSubjects
        end

        self.subjects = filteredSubjects or {}
        self.selected.subject = clamp(self.selected.subject, 1, math.max(1, #self.subjects))

        local subject = self:getSelectedSubject()
        if subject then
            self.questions = self.engine:getQuestionTypesForSubject(subject.id)
        else
            self.questions = self.engine:getQuestionTypes()
        end

        if #self.questions == 0 then
            self.questions = self.engine:getQuestionTypes()
        end

        self.selected.question = clamp(self.selected.question, 1, math.max(1, #self.questions))

        local question = self:getSelectedQuestion()
        self.focusTokens = { "(none)" }
        if subject and question then
            local focus = self.engine:getFocusTokens(subject.id, question.id)
            for _, token in ipairs(focus or {}) do
                self.focusTokens[#self.focusTokens + 1] = token
            end
        end

        self.selected.focus = clamp(self.selected.focus, 1, math.max(1, #self.focusTokens))
    end

    function modal:setSelection(field, index)
        if field == "npc" then
            self.selected.npc = clamp(index, 1, math.max(1, #self.encounterNPCs))
            self.selected.subject = 1
            self.selected.question = 1
            self.selected.focus = 1
            self:refreshSubjectsQuestionAndFocus()
            return
        end

        if field == "subject" then
            self.selected.subject = clamp(index, 1, math.max(1, #self.subjects))
            self.selected.question = 1
            self.selected.focus = 1
            self:refreshSubjectsQuestionAndFocus()
            return
        end

        if field == "question" then
            self.selected.question = clamp(index, 1, math.max(1, #self.questions))
            self.selected.focus = 1
            self:refreshSubjectsQuestionAndFocus()
            return
        end

        if field == "motif" then
            self.selected.motif = clamp(index, 1, math.max(1, #self.motifs))
            return
        end

        if field == "focus" then
            self.selected.focus = clamp(index, 1, math.max(1, #self.focusTokens))
        end
    end

    function modal:getOptionsForField(field)
        if field == "npc" then return self.encounterNPCs end
        if field == "subject" then return self.subjects end
        if field == "question" then return self.questions end
        if field == "motif" then return self.motifs end
        if field == "focus" then return self.focusTokens end
        return {}
    end

    function modal:cycleField(delta)
        local count = #FIELD_ORDER
        local nextValue = self.activeField + delta
        if nextValue < 1 then nextValue = count end
        if nextValue > count then nextValue = 1 end
        self.activeField = nextValue
    end

    function modal:adjustActiveFieldSelection(delta)
        local field = FIELD_ORDER[self.activeField]
        local options = self:getOptionsForField(field)
        if #options == 0 then
            return
        end

        local selectedIndex = self.selected[field] or 1
        selectedIndex = selectedIndex + delta
        if selectedIndex < 1 then
            selectedIndex = #options
        elseif selectedIndex > #options then
            selectedIndex = 1
        end

        self:setSelection(field, selectedIndex)
    end

    function modal:submit()
        if not self.isVisible then
            return
        end

        local encounterNPC = self:getSelectedEncounterNPC()
        local subject = self:getSelectedSubject()
        local question = self:getSelectedQuestion()
        local motif = self:getSelectedMotif()
        local focus = self:getSelectedFocus()

        local result = self.engine:adjudicate({
            actor = self.actor,
            party = self.pendingAction and (self.pendingAction.party or self.pendingAction.guild) or nil,
            action = self.pendingAction,
            challengeController = self.challengeController,
            roomId = self.roomId,
            subjectId = subject and subject.id or nil,
            questionType = question and question.id or nil,
            motif = motif,
            focus = focus,
            targetNpcId = encounterNPC and not encounterNPC.isRoomContext and encounterNPC.id or nil,
            targetNpcBlueprintId = encounterNPC and not encounterNPC.isRoomContext and encounterNPC.blueprintId or nil,
        })

        result.selection = {
            npcId = encounterNPC and not encounterNPC.isRoomContext and encounterNPC.id or nil,
            npcBlueprintId = encounterNPC and not encounterNPC.isRoomContext and encounterNPC.blueprintId or nil,
            subjectId = subject and subject.id or nil,
            questionType = question and question.id or nil,
            motif = motif,
            focus = focus,
        }

        self.eventBus:emit(events.EVENTS.BID_LORE_COMPLETE, {
            actor = self.actor,
            action = self.pendingAction,
            result = result,
        })

        self:hide()
    end

    function modal:cancel()
        if not self.isVisible then
            return
        end

        local result = {
            verdict = "rephrase_needed",
            reason = "Lore bid withdrawn before the question was finalized.",
            loreSpend = false,
            suggestedQuestionTypes = {},
            scoreBreakdown = {},
            cancelled = true,
        }

        self.eventBus:emit(events.EVENTS.BID_LORE_COMPLETE, {
            actor = self.actor,
            action = self.pendingAction,
            result = result,
        })

        self:hide()
    end

    function modal:drawSection(field, label, x, y, w, h)
        local options = self:getOptionsForField(field)
        local selectedIndex = self.selected[field] or 1
        local isActive = (FIELD_ORDER[self.activeField] == field)

        love.graphics.setColor(self.colors.section_bg)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)

        local borderColor = isActive and self.colors.section_active or self.colors.section_border
        love.graphics.setColor(borderColor)
        love.graphics.rectangle("line", x, y, w, h, 6, 6)

        love.graphics.setColor(self.colors.title)
        love.graphics.print(label, x + 8, y + 6)

        local listTop = y + 28
        local footerHeight = 18
        local rowHeight = 22
        local visibleRows = math.max(1, math.floor((h - 28 - footerHeight - 8) / rowHeight))

        if #options == 0 then
            love.graphics.setColor(self.colors.dim_text)
            love.graphics.print("(none available)", x + 10, listTop + 4)
            love.graphics.printf("0/0", x + 8, y + h - footerHeight - 2, w - 16, "right")
            return
        end

        local startIndex = selectedIndex - math.floor(visibleRows / 2)
        startIndex = clamp(startIndex, 1, math.max(1, #options - visibleRows + 1))
        local endIndex = math.min(#options, startIndex + visibleRows - 1)

        for index = startIndex, endIndex do
            local rowY = listTop + (index - startIndex) * rowHeight
            local isSelected = index == selectedIndex
            local isHovered = self.hoveredOption and self.hoveredOption.field == field and self.hoveredOption.index == index

            if isSelected then
                love.graphics.setColor(self.colors.row_selected)
                love.graphics.rectangle("fill", x + 6, rowY, w - 12, rowHeight - 2, 4, 4)
            elseif isHovered then
                love.graphics.setColor(self.colors.row_hover)
                love.graphics.rectangle("fill", x + 6, rowY, w - 12, rowHeight - 2, 4, 4)
            end

            love.graphics.setColor(isSelected and self.colors.title or self.colors.text)
            local rowLabel = string.format("%d. %s", index, optionLabel(field, options[index]))
            love.graphics.printf(rowLabel, x + 12, rowY + 3, w - 20, "left")

            self.optionBounds[#self.optionBounds + 1] = {
                field = field,
                index = index,
                x = x + 6,
                y = rowY,
                w = w - 12,
                h = rowHeight - 2,
            }
        end

        love.graphics.setColor(self.colors.dim_text)
        love.graphics.printf(
            string.format("%d/%d", selectedIndex, #options),
            x + 8,
            y + h - footerHeight - 2,
            w - 16,
            "right"
        )
    end

    function modal:drawSelectionSummary(x, y, w, h)
        local encounterNPC = self:getSelectedEncounterNPC()
        local subjectRef = self:getSelectedSubject()
        local question = self:getSelectedQuestion()
        local motif = self:getSelectedMotif() or "(none)"
        local focus = self:getSelectedFocus() or "(none)"

        local subject = subjectRef and self.engine:getSubject(subjectRef.id) or nil
        local answer = subject and question and subject.answers and subject.answers[question.id] or nil

        love.graphics.setColor(self.colors.section_bg)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)
        love.graphics.setColor(self.colors.section_border)
        love.graphics.rectangle("line", x, y, w, h, 6, 6)

        love.graphics.setColor(self.colors.title)
        love.graphics.print("Selection Preview", x + 8, y + 6)

        love.graphics.setColor(self.colors.text)
        local selectionText = string.format(
            "NPC: %s | Subject: %s | Question: %s | Motif: %s | Detail Cue: %s",
            encounterNPC and encounterNPC.name or "(none)",
            subjectRef and subjectRef.name or "(none)",
            question and question.name or "(none)",
            tostring(motif),
            tostring(focus)
        )
        love.graphics.printf(selectionText, x + 8, y + 28, w - 16, "left")

        local previewY = y + 50
        if self.npcFilterFallback then
            love.graphics.setColor(self.colors.warn)
            love.graphics.printf(
                "No authored lore is keyed to this NPC yet; showing room-context subjects.",
                x + 8,
                previewY,
                w - 16,
                "left"
            )
            previewY = previewY + 16
        end

        if answer and answer.summary then
            love.graphics.setColor(self.colors.dim_text)
            love.graphics.printf("Authored answer preview: " .. answer.summary, x + 8, previewY, w - 16, "left")
        else
            love.graphics.setColor(self.colors.warn)
            love.graphics.printf("No authored answer for the current question on this subject.", x + 8, previewY, w - 16, "left")
        end
    end

    function modal:drawButtons()
        local buttonY = self.y + self.height - 46
        local buttonW = 150
        local buttonH = 30
        local padding = 12

        local cancelX = self.x + self.width - buttonW * 2 - padding * 2
        local submitX = self.x + self.width - buttonW - padding

        local cancelHover = self.hoveredButton == "cancel"
        local submitHover = self.hoveredButton == "submit"

        love.graphics.setColor(cancelHover and self.colors.button_hover or self.colors.button_bg)
        love.graphics.rectangle("fill", cancelX, buttonY, buttonW, buttonH, 4, 4)
        love.graphics.setColor(self.colors.button_border)
        love.graphics.rectangle("line", cancelX, buttonY, buttonW, buttonH, 4, 4)
        love.graphics.setColor(self.colors.text)
        love.graphics.printf("Cancel", cancelX, buttonY + 8, buttonW, "center")

        love.graphics.setColor(submitHover and self.colors.button_primary or self.colors.button_bg)
        love.graphics.rectangle("fill", submitX, buttonY, buttonW, buttonH, 4, 4)
        love.graphics.setColor(self.colors.button_border)
        love.graphics.rectangle("line", submitX, buttonY, buttonW, buttonH, 4, 4)
        love.graphics.setColor(self.colors.title)
        love.graphics.printf("Submit Bid Lore", submitX, buttonY + 8, buttonW, "center")

        self.cancelButtonBounds = { x = cancelX, y = buttonY, w = buttonW, h = buttonH }
        self.submitButtonBounds = { x = submitX, y = buttonY, w = buttonW, h = buttonH }
    end

    function modal:draw()
        if not self.isVisible then
            return
        end

        local sw, sh = love.graphics.getDimensions()
        love.graphics.setColor(self.colors.backdrop)
        love.graphics.rectangle("fill", 0, 0, sw, sh)

        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 8, 8)
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 8, 8)
        love.graphics.setLineWidth(1)

        local actorName = self.actor and self.actor.name or "Unknown"
        local loreBids = self.actor and (self.actor.loreBids or 0) or 0

        love.graphics.setColor(self.colors.title)
        love.graphics.printf("Bid Lore", self.x, self.y + 12, self.width, "center")

        love.graphics.setColor(self.colors.text)
        love.graphics.printf(
            string.format("%s | Lore Bids Remaining: %d", actorName, loreBids),
            self.x,
            self.y + 34,
            self.width,
            "center"
        )

        love.graphics.setColor(self.colors.dim_text)
        love.graphics.printf(
            "Tab/Left/Right: change panel  |  Up/Down: choose option  |  Enter: submit",
            self.x,
            self.y + 56,
            self.width,
            "center"
        )
        love.graphics.printf(
            "Encounter NPC narrows subjects. Detail Cue is optional.",
            self.x,
            self.y + 70,
            self.width,
            "center"
        )

        self.optionBounds = {}

        local contentPadding = 14

        local topGap = 10
        local topSectionHeight = 148
        local topY = self.y + 92
        local topTotalWidth = self.width - contentPadding * 2
        local topSectionWidth = math.floor((topTotalWidth - topGap * 2) / 3)
        local topSectionWidthLast = topTotalWidth - topSectionWidth * 2 - topGap * 2

        local topLeftX = self.x + contentPadding
        local topMidX = topLeftX + topSectionWidth + topGap
        local topRightX = topMidX + topSectionWidth + topGap

        local rowGap = 12
        local bottomGap = 14
        local bottomSectionHeight = 148
        local bottomY = topY + topSectionHeight + rowGap
        local bottomTotalWidth = self.width - contentPadding * 2
        local bottomSectionWidth = math.floor((bottomTotalWidth - bottomGap) / 2)
        local bottomSectionWidthLast = bottomTotalWidth - bottomSectionWidth - bottomGap
        local bottomLeftX = self.x + contentPadding
        local bottomRightX = bottomLeftX + bottomSectionWidth + bottomGap

        self:drawSection("npc", "Encounter NPC", topLeftX, topY, topSectionWidth, topSectionHeight)
        self:drawSection("subject", "Subject", topMidX, topY, topSectionWidth, topSectionHeight)
        self:drawSection("question", "Question", topRightX, topY, topSectionWidthLast, topSectionHeight)
        self:drawSection("motif", "Motif", bottomLeftX, bottomY, bottomSectionWidth, bottomSectionHeight)
        self:drawSection("focus", "Detail Cue (optional)", bottomRightX, bottomY, bottomSectionWidthLast, bottomSectionHeight)

        self:drawSelectionSummary(
            self.x + contentPadding,
            self.y + self.height - 136,
            self.width - contentPadding * 2,
            84
        )

        self:drawButtons()
    end

    local function pointInBounds(x, y, bounds)
        return bounds and
            x >= bounds.x and x <= bounds.x + bounds.w and
            y >= bounds.y and y <= bounds.y + bounds.h
    end

    function modal:mousepressed(x, y, button)
        if not self.isVisible or button ~= 1 then
            return false
        end

        for _, bounds in ipairs(self.optionBounds) do
            if pointInBounds(x, y, bounds) then
                self.activeField = FIELD_INDEX[bounds.field] or self.activeField
                self:setSelection(bounds.field, bounds.index)
                return true
            end
        end

        if pointInBounds(x, y, self.submitButtonBounds) then
            self:submit()
            return true
        end

        if pointInBounds(x, y, self.cancelButtonBounds) then
            self:cancel()
            return true
        end

        return true
    end

    function modal:mousemoved(x, y)
        if not self.isVisible then
            return
        end

        self.hoveredOption = nil
        self.hoveredButton = nil

        for _, bounds in ipairs(self.optionBounds) do
            if pointInBounds(x, y, bounds) then
                self.hoveredOption = {
                    field = bounds.field,
                    index = bounds.index,
                }
                break
            end
        end

        if pointInBounds(x, y, self.submitButtonBounds) then
            self.hoveredButton = "submit"
        elseif pointInBounds(x, y, self.cancelButtonBounds) then
            self.hoveredButton = "cancel"
        end
    end

    function modal:keypressed(key)
        if not self.isVisible then
            return false
        end

        if key == "escape" then
            self:cancel()
            return true
        end

        if key == "return" or key == "kpenter" then
            self:submit()
            return true
        end

        if key == "tab" or key == "right" then
            self:cycleField(1)
            return true
        end

        if key == "left" then
            self:cycleField(-1)
            return true
        end

        if key == "up" then
            self:adjustActiveFieldSelection(-1)
            return true
        end

        if key == "down" then
            self:adjustActiveFieldSelection(1)
            return true
        end

        local numeric = tonumber(key)
        if numeric then
            local field = FIELD_ORDER[self.activeField]
            local options = self:getOptionsForField(field)
            if numeric >= 1 and numeric <= #options then
                self:setSelection(field, numeric)
            end
            return true
        end

        if key == "c" then
            self:cancel()
            return true
        end

        if key == "s" then
            self:submit()
            return true
        end

        return true
    end

    return modal
end

return M
