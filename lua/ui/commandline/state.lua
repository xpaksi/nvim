local M = {}

local function normalize_chunks(chunks)
	local normalized = {}
	local text = {}
	for _, chunk in ipairs(chunks or {}) do
		local value = type(chunk[2]) == "string" and chunk[2] or ""
		normalized[#normalized + 1] = {
			attrs = type(chunk[1]) == "table" and chunk[1] or {},
			text = value,
			hl_id = tonumber(chunk[3]) or 0,
		}
		text[#text + 1] = value
	end
	return normalized, table.concat(text)
end

function M.new()
	return { levels = {}, active_level = nil, block = nil }
end

local function select_active(state)
	local active
	for level in pairs(state.levels) do
		if not active or level > active then
			active = level
		end
	end
	state.active_level = active
end

function M.show(state, content, pos, firstc, prompt, indent, level, hl_id)
	level = tonumber(level) or 1
	local chunks, text = normalize_chunks(content)
	state.levels[level] = {
		level = level,
		chunks = chunks,
		text = text,
		pos = math.max(0, math.min(tonumber(pos) or 0, #text)),
		firstc = firstc or "",
		prompt = prompt or "",
		indent = math.max(0, tonumber(indent) or 0),
		prompt_hl_id = tonumber(hl_id) or 0,
		special = nil,
	}
	state.active_level = level
end

function M.position(state, pos, level)
	local item = state.levels[tonumber(level) or 1]
	if item then
		item.pos = math.max(0, math.min(tonumber(pos) or 0, #item.text))
		item.special = nil
	end
end

function M.special(state, char, shift, level)
	local item = state.levels[tonumber(level) or 1]
	if item then
		item.special = { char = char or "", shift = not not shift }
	end
end

function M.hide(state, level)
	state.levels[tonumber(level) or state.active_level or 1] = nil
	select_active(state)
end

function M.block_show(state, lines)
	state.block = {}
	for _, line in ipairs(lines or {}) do
		local chunks, text = normalize_chunks(line)
		state.block[#state.block + 1] = { chunks = chunks, text = text }
	end
end

function M.block_append(state, line)
	state.block = state.block or {}
	local chunks, text = normalize_chunks(line)
	state.block[#state.block + 1] = { chunks = chunks, text = text }
end

function M.block_hide(state)
	state.block = nil
end

function M.reset(state)
	state.levels = {}
	state.active_level = nil
	state.block = nil
end

return M
