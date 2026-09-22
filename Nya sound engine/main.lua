--[[
Nya audio engine 1.0.0

MIT License

Copyright (c) 2026 HanamileH

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local Nya = {
	-- List of sounds currently playing
	current = {},
	next_id = 1,
}

-- Load sound from compressed data
function Nya.load_sound(sound_data)
	if type(sound_data) ~= "string" then error("Audio data is not a string!") end

	local function b64_decode(data)
		local BASE64_CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local REMAINDER_CHARS = "#$%&="

		local BASE64_CODES = {}
		local REMAINDER_CODES = {}

		for i = 1, #BASE64_CHARS do
			local binary_code = ""
			local char = BASE64_CHARS:sub(i, i)
			for j = 1, 6 do
				binary_code = binary_code .. tostring(((i - 1) >> (6 - j)) & 1)
			end

			BASE64_CODES[char] = binary_code
		end

		for i = 1, #REMAINDER_CHARS do
			REMAINDER_CODES[REMAINDER_CHARS:sub(i, i)] = i
		end

		local result = {}
		local remainderSize = 0

		for i = 1, #data do
			local char = data:sub(i, i)

			if i == #data and REMAINDER_CODES[char] then
				remainderSize = REMAINDER_CODES[char]
			elseif BASE64_CODES[char] then
				result[i] = BASE64_CODES[char]
			else
				error("Invalid character in base64 string: " .. char)
			end
		end

		result = table.concat(result)

		if remainderSize > 0 then result = result:sub(1, -7 + remainderSize) end

		return result
	end

	local function lzw_decode(input)
		local dictionary = {}

		for i = 1, 16 do
			dictionary[i - 1] = string.sub("0123456789abcdef", i, i)
		end

		local next_free = 16
		local index_size = 4
		local small_index_size = index_size - 1

		local result = {}

		local pos = 1

		local function get_next_code()
			if index_size == small_index_size then
				local code = input:sub(pos, pos + index_size)
				pos = pos + index_size + 1
				return tonumber(code, 2)
			end

			local is_long = tonumber(input:sub(pos, pos), 2)

			if is_long == 0 then
				local code = input:sub(pos + 1, pos + small_index_size)
				pos = pos + small_index_size + 1
				return tonumber(code, 2)
			else
				local code = input:sub(pos + 1, pos + index_size)
				pos = pos + index_size + 1
				return tonumber(code, 2) + (1 << small_index_size)
			end
		end

		local old_code = get_next_code()

		table.insert(result, dictionary[old_code])

		while pos < #input do
			local new_code = get_next_code()

			local frag = dictionary[new_code]
			local new_string

			if frag then
				new_string = frag
			else
				new_string = dictionary[old_code]
				new_string = new_string .. new_string:sub(1, 1)
			end

			table.insert(result, new_string)

			dictionary[next_free] = dictionary[old_code] .. new_string:sub(1, 1)
			next_free = next_free + 1
			old_code = new_code

			if next_free & (next_free + 1) == 0 then
				index_size = index_size + 1
			end

			if (1 << (index_size - 1)) * 3 == next_free then
				small_index_size = small_index_size + 1
			end
		end

		return table.concat(result)
	end


	-- Check the magic number
	if sound_data:sub(1,4) ~= "ROK_" then error("Data is not a OKCodec audio!") end

	-- Unpack the header
	local header = b64_decode(sound_data:sub(5, 10))

	local audio_depth = tonumber(header:sub(1, 4), 2) + 1
	local max_sample = 2 ^ audio_depth

	local range_depth = tonumber(header:sub(5, 8), 2) + 1
	local max_range  = 2 ^ range_depth

	-- Fragments size
	local fragment_size = math.floor(2 ^ tonumber(header:sub(9, 12), 2))

	-- Audio length
	local audio_length = tonumber(header:sub(13, 36), 2)

	-- Decode the audio data
	local data = b64_decode(sound_data:sub(12, -1))

	local volume_data = lzw_decode(data:sub(1, audio_length))
	local wave_data = lzw_decode(data:sub(audio_length + 1, -1))

	local fragments_per_tic = 128 // fragment_size

	return {
		is_audio = true,
		audio_depth = audio_depth,
		max_sample = max_sample,
		range_depth = range_depth,
		max_range = max_range,
		fragment_size = fragment_size,
		audio_length = audio_length,
		volume_data = volume_data,
		wave_data = wave_data,
		fragments_per_tic = fragments_per_tic,
	}
end

-- Add sound for playback
function Nya.play(sound, loop, volume)
	if type(sound) ~= "table" or not sound.is_audio then error("Invalid sound data!") end
	if loop == nil then loop = false end
	if volume == nil then volume = 1 end

	Nya.current[Nya.next_id] = {
		data = sound,
		adr = 0,
		loop = loop,
		volume = volume,
		low_range = 0,
		high_range = 0,
		value = 0
	}

	Nya.next_id = Nya.next_id + 1

	return Nya.next_id - 1
end

-- Stop the specified sound
function Nya.stop(sound_id)
	Nya.current[sound_id] = nil
end

-- Is the specified sound playing
function Nya.is_alive(sound_id)
	return Nya.current[sound_id] ~= nil
end

-- Main loop for audio engine
function Nya.update()
	local pcm_buffer = {}
	for i = 1, 128 do
		pcm_buffer[i] = 0
	end

	-- Add each sound to the buffer
	for id, sound in pairs(Nya.current) do
		local data = sound.data

		for part = 1, data.fragments_per_tic do
			local highDelta = tonumber(data.volume_data:sub(sound.adr * 2 + 1, sound.adr * 2 + 1), 16)
			local lowDelta  = tonumber(data.volume_data:sub(sound.adr * 2 + 2, sound.adr * 2 + 2), 16)

			if (highDelta == nil) or (lowDelta == nil) then
				Nya.current[id] = nil
				break
			end

			sound.low_range  = (sound.low_range  + lowDelta)  % data.max_range
			sound.high_range = (sound.high_range + highDelta) % data.max_range

			local frag = data.wave_data:sub(sound.adr * data.fragment_size + 1, sound.adr * data.fragment_size + data.fragment_size)

			if #frag < data.fragment_size then
				Nya.current[id] = nil
				break
			end

			-- Playback
			local low  = sound.low_range / 15 * 255
			local high = sound.high_range / 15 * 255

			for i = 0, data.fragment_size - 1 do
				local offset = i + (part - 1) * data.fragment_size
				local valueDelta = tonumber(frag:sub(i + 1, i + 1), 16)

				sound.value = (sound.value + valueDelta) % data.max_sample

				local wave = low + sound.value / data.max_sample * (high - low)

				pcm_buffer[offset + 1] = pcm_buffer[offset + 1] + wave * sound.volume - 127.5
			end
			sound.adr = sound.adr + 1
		end
	end

	-- Playback 8 bit PCM
	for i = 1, 128 do
		local value = pcm_buffer[i] + 127.5

		value = (value < 0) and 0 or (value > 255) and 255 or value

		poke(0x14E23 + i, value)
	end
end
