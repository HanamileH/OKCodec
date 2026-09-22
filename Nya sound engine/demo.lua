-- title:   Nya audio engine demo
-- author:  HanamileH
-- desc:    TIC-80 PCM audio engine
-- license: MIT License
-- version: 0.1
-- script:  lua

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


	-- Checkthe magic number
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

-- Save any desired sounds here
-- (or use a different array if you wish)
local sounds = {
	spawn = Nya.load_sound([[ROK_E1AADE|iwaC48ZT6CqC0eF0TRZY42lTU+ya+eaSYQzrfNCIxxvjoxUYCAIduoA671Y+c1zUVTZW46Uv33bdQL12cnKCzZ87iutSchuvr34dB+TE7d0OlTlw91sF53PMpqSvKtr6cVLCXzSmaPgYM824DlxMpKBTe09vdW15gKrtGcpr+YYZWDiZzOxy8LQ1cTMvsnGvkGfk2nFa5aPk6TUBca2ymdRl2btfAn7GvIl8/X7/f+Bg4WHiYuNji123pdgINZ0zrOQKjTIospBsLxKubg2sLmsv8A3xcSwlczW3Z1RnVvZIz3hH0M/B+vbJQ9L5TEhkl3ihbLo49RrBR6LxPAQXFw3Gy+94/KZKRyuN4WUYSeT53NHgRp9BztT00+]]),
	toolgun1 = Nya.load_sound([[ROK_E1AAHa|g4WvNxEkxCA9UbxEeCe3cO4Lee3CBkrrPpytylozl58v36NRe9VwXKuKtUi1q8uxn5YN03n38efXv59EMiee+/gE6wvuqmEcEgNcxbTadYQClhBkxZBpwgUz6SiWtzIGCPjTt33XJt7TeDo6NdJmqxqg8LUWorHuUTTFodR4rzOO8VLJVZNIhTT7WxsJNbneZJZ0EdHH1llTPzVkQNxFq/R2yLPxYy2KU1BLH5OahrBdPQNPqgAU6hfZR7NyS+DHdkaigaW1acF5j8UXq9dF96iarrb2WmE5cR4bBsIxeS8hTKlJDHH/TZcDQUGmdK5OS2HrHebLcQ8LRh12WW7KbkY6v2Zrd6GuGTYsSz7945i6cx6OxS4DEgRX57TymD025Wu7rDG5J+StDngJThb7ZpsW1ceLFq7TuBZ2RTytV2xPkzRpnR7ZgYnSUCoTfbXccks6K5rsrO9beL0CEotzqes2eNv105O5boHLM/zbPzqFwObyoZKL1MZBCrJG6XZLL0ItKO/mOnkblMOVkNjW3DYZDQ+6me/30WX1e19yp1ecXisPRA3/AYWcXrFTWbVWEr48SIz25M42j4i7qaPm+kNIbU/G2yj1Cs4PGPiqHdrqQewmcrjQMy8XBk6WH0HOkBHx59x5XZ/cxukb8wsGsJGu6Hl7/YUPHanBQ5E3bPW3rZqCZe1vHAHHt3HS8qxdylwxq9SAaPvC6XyhsQjDXOGbXmYHiffic1MIBXQ2vCqHZTti0WW/YfuuyaWqOyaJlmi8GwSbrmjzE0KO60gXA8TU0hQ1fEpX1G8mW40qduKKscxTCSyV5LEmUGXDapTOG43hl7NkP5jSGb3BYCCflMYRGptjTH8co+umvmeRUJiN9G/LLduLOLOy+5tWszEKIg+q3QcY7pnUNaetSyK0cC1m3aUprUMRyjZMdk6/6XkzbrYhPEtCuu0qK1LR6E33QsGxvY9N3KVa0nvgNs1WQd23HfbQ3jA881fR1vyXIzzp9NcvjPIWX0WuYJwe67XimKr/huUwXb986mM66K+L4rUHNM3O2TpfdVnufgeD4Xh+IGQ$]]),
	toolgun2 = Nya.load_sound([[ROK_E1AAJI|g4WGhMLWuKIIEsuEQGt1z36g6u1fdNVlmBdRtXTzX70CDNk0bF7NdoTK1GZQw6LM3fsx55uefc8TNnb77wYcVHHlzZ9GnVr2ZSDOt6PmQ3lnVtXxjHBDdLZJxRKAIgxVVgBsvZQbW6W7zQZlO45fYryclCpVTtW9sBTPAo1o2xFDrc+OyY8xs4N3Z91giWqIlG89saiyaUBnH6zXq/4YURa1lrF/CWCjDSu8dpiVVfbycK9o6m1krmon66myM2XZ1lLdZe5SVFDAwTfYkJxVqOMOHkyuL2wFI8uYanwaZskYxlKITqnUqxnpE+zmhvDiH0baTugyJFjX9O4bZqwwrG0mz3L2LLEm05/RWjYTYpFfxeT28duKlaVZV6GwkoenTlFXyUoRXHrvWrHLIhSyOnxTDJMHtaDE75HJ1lZ5C2m42M6JMTbrE5oFCS8Jn5JLtIhQHWYVVocvnIxBh9/07lTs7p9RvtxGYQ6ZTZ6Nx2t9yEjpMDovCABDEIfUlFBJXacJlvYhert9D7Nkz16bMkod9Uqo1MOgT3WEp18xly5lH2BlEakZ0xUsTPZHVbKxClDVmUSH1aINQTXiCNS0qJG5Q72nJvNsVl33XoFdUULJg1J3Wl0/oWyGTm1QZtBVYpK9ZN7bKZ9JYPooa22ZoJLQtJthS647BaroeNMUSu929L1fbIq7w9Q4q5a1NVscMyrW3xim5pq173+TWmcXLpOWgjaMnVfT9HTn/17L9IxmPH348z+vpL41rMimrapOY1rBD2rNeBYDf1xvdc2pTVf19bdtWxiyzwa/8AqK0rZxSvq9wOzYEU9T4VgMdU/VFUV5hd75Pk975fjuK4vleY1kt8wzLOs8ofFMexXE7ZiXJr4Zb0tqrqq0PTblsWE8j0fOM/xaTcazvVctqmXq/1jVFtVmkZdnudYZrOgbDoOnaflGxUxPObjDcaW1PM9V0ybq31zE3fqWz6Pn214BcmwbVV22bHqHCY4LGNWNxZ4gWNxNuqq4rtRaGukXWPDUTLsTUnZ+23xxu00fkXCYVXPBaVrHBaXPVFvPf+K6fZpQOG393xB3fc9bpmFWzz2uubF004WVjfcu3qO+MmQ1z1nm5zSvrcHwvcaX5XA+xyvv2tZnp7vPyZ6SdfK8LSe59TZtw2XbyjWGbblvHpfV+OgZDqfb/f/7D1lQt3WfdlqilddXXA1bEJZYVWs7gDkVnb1uuLbuFVVZOG09jmGSJVdp2OxVXOxPtbYJIUv4zMls5bk2NYhl1cZhP+ZXrl8t21bErMDdK7Xk1aPQxg1UrM6d6RrEE+RviulVsrN11/j9+UWxmNX9e+VlvBOZarO2CwXp1X5QasaLTNUPYEKOaa/hMgrLhc0yHsmd6fgeWUBp1oX7s2D7rm++antWt6DbmKYfa21qOkkX6hePD8ZJE56M1+YvrD7Kc1zfOc6CQ%]]),
	gmod_info = Nya.load_sound([[ROK_I1AAD6|g4a3u5SERwA8A54bZbX2a46iwvHEGZW9LGPVS/GHjhAy+RDecYrnmL24Y21g0qyvuilOcIRgAhxgc9dwA9OgBhwgr9abFByzJ2metqltxoUpxNvKFDZEqhxfyhOKemTIq2RGKyc5bSCmTc5df0rNMWroS5FvO9LQ3l1YRrE/ambetqZ2rrKnEsbO1XYOfayz6hKbGlcZF3hZGdj8GsZ4N7curvG65gq/pp7mvJ6vTXkVkU/loeDDfSDtRGy8W4RfcQDvJv9bnNTkaCtw1n+GWWSqbMtsgo9PO5CqgiV8bLB9sGSDkIaCsA3mIgQHY+nbtFuVHI1qPzG/yETq09JaXTb6LT6wYxXs1zP7BeMK/3PLFgLljMHBTi3A2bAQNv0RjdjfRga7n1zTZ82u+n0lyue1tZdkQW2m+T2e3sGiQNDqNNt9Lkjq5by7bnnZ7iIWrR+pmOFk1g8ox5OOCj3DwcS113yN54ZeYzzdm7pv4++76HdYzuVxI9+XB9KAbxE7NyWJGH2DGIvkTtekmF0txmEF7Uw8FuosY67fmVTOZCTHL4uVArDpVzmiKKoFKJQBSERJo8lj9AmZAGGziYwtMoK8elgFAuvvYBjYEj0kag3xY7HBD2+bGpHzoszJzfht6IaOerMfaz5S7gq5/Z8Pi8Yg]]),
	portalgun = Nya.load_sound([[ROK_M1AAdw|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]]),
	blue_portal = Nya.load_sound([[ROK_I1AAKF|g4a3wLiAa7DEyIdDmlA2KcjHjnCIAk0F0E9I4Qc0gAI+/OSBOhYU2GF8tZZjQmutX4YuOLoqsADv5/m8+UUXD8NrRp1aM+vdv4ceXPp17d96A4bAd6tSkp2OG+e2iyXS6mHDjG+zCam1mWNVeuqKZpUaTXafBGACyDBD3wcm1J8IUEIDLLiRh+ukJDVWBy48UFdYEpSd+RtlUBgjVMBXHbiXD4rM9UwevG1e7JhpfDLKb8jgBwtwZUHcCUNlwwdqWhSYKH1II2e3ChnH0zs5scunANV5yQjb/emMz3m5BKe8m+T0X4i6o8XLUI7RzMZI2aad5VjjIQ8NICDQaucemsuSgQG4QgwBgseqWdEXtsymuaC6nUTraGNuHWvnYOLCY7tgtsMqMAEwOCl9NN8Fgqqpy2BzEhjrji3G/1R5zE3plawJddpvjq0ZYPQTqqwNVokoQb+VWycUqHkV008RxMK0kWrlRWaq2WiryxZ0xdJTDbbbIzuSZ61azlJqZkyXqVW7U7Ijzmh3fMKB3Pyu5daQ9/F4PcatPGE61cXOkQG2HuihXFulc8fB78ENJ9GTAYHnfBm8QoZStfiSHakQcXZnbiYeajUvG3LFZK5Lh348RDemtAWfH6NmWRL2noisADFpyMS4vK2jUULQNcRslb5mVENDzSODNWl4WyccBKh7ziZsvqsLXqgYilFh0SCbjkOCcduQpkCfz7oTcJ7W0+zbzRR5eKcEPElFC2pNWQ2pWEUU6OSQMBIaVb8z/QizhSghAiJp8RsVXiK6BipbEH9gjoWrCuzyksMlyWYeAMCxLJUcjlkFac8NIRrtWQbfpqa79PyYTcOSg28BmKZBGJMGK6YOabriXEip4TcImA0C1hnko3pdcBnEr3nRBWTyrHx+D5luGWhmhsvzaIz9LubGBLVjqlmSFFtqR3hFwDGbKAp/HhA7j+ubJo0YUady3sOIjaoZB2Y06DCjPdNsPHFtIfo1TmATpaXCnKX7Fw/lIis634ejqNzwbxcT8vhc4Lw+7BYrLEGCTZqU/bUaqvIafS3XGDE+iEFFnmTqrMmidsZiHQBEToRojxQsw5RLuRAECEvnZzvN1GUkdjTjOzrorUv9GFWyhFve6YU7Kox61Siy4JSfBSO99o4lp/LzYs+pBW9PO3RzcMT/gqLUzLCp8LaC7pn1br0exGkgwS7C7T2oUgo1E59hF3p8wXE19xBGqXHbHR4m2/mGOw4aYt8bRccRfFbbQTSPnI+zUyh47dMoFhKtMBhTOAPgFN8ABfGMSiPAOO72JOxW+il9hIIMWgXGQBwQAWD4KtSrrXl4xpjDdiJwt/NckcOcro2S4tGxW9052pdCaxtZIWYVqdr3PdJLiC7Xsx982Xn68cRvvBiBwdQuChbCR8wnhzXc6/eNbLj5+xrH7qf2LKstxq8zMq9NXcYR6SZYNN73wodXwCYroVOKRM6lJMwhONa262juw2zE8StvuDHw/dZf73csc710buS7aj77aNdrtHb+TDIrvPv+QSN5fXlFqHjLp1ve+6wby+yOyv47DoRUFFfElBD9cs9ZWqsLyfnq3p+3EvCGD5G++zn0HdURRdv7RwvLPqlhlzBKRlRoDwRxfotaKFtKUHnHK9N7T2te2aNlWkuTciutf66UDK51cQYTq9ai3+Jq6wxtJJcmrz3aohQ6tqekFb0xblszdKtduqAYpk5bOglg8f2DtHYlboMNfE8G8H4/wxPS7cJLs3xeMvKaGRFbFbxqeIbkXZvnazFdjsZ3XspgSx1lrT49KKf+Fcd4TzXinNNAcyYaxPhzDMjs15wam4dl86Z9z9mq8+IcfYeztB/DONbYWju5k6VmJLrFDGu52FbGPbgKxBd4MsVk2socY6yJQu7GQIx6KsW8FkUkpDWWwOfsa2JxLn+tVzatTihPCfM1ktYa51ZnnXWvdfW/rjoXPuYtN2+Hd3UfwbXahST6Y2ZbSo2tdTxL1tsyvuQcga/21n0&]]),
	orange_portal = Nya.load_sound([[ROK_I1AAMo|g4a3wblZwAgeBhXsooDnE98xGhIEskEEOzPMm0Nfc5lxxRN5tZw00bC7sAODvSEsOvFkxthPPAhGynwQcMLAjdwqUuaDtenV2k6lKF13RenX11Od/dTVqLC/xMXGx8jJysvMzYJABwHO84ri0a3rqstjurk2v3vDpRzvM3S1avZizfxBl34lIw3r7rMautJHVB2vJjZ80eYMMOFRXTD95NcVDiZB6KJhTcNA+DDZoul2ecwQqrQU+CA5jXSopXB/DXAQU7JYUBWFwdHFy+TSVgAFd1MNLXUa2QE6XUThoyzrLa+qdRXAPEK/kXXe/JagLjta1KSbWMsUuyxNFIwkwcIcjHKLRBqjTsc0PYqtd6rKQ7O/f8i7MWMwziWhYS6RwBKkkUZ/n+OE6BanFMKwZ6xCR6TErO9FA52WpqzUaXdyZRkl0cjO8ESZJ0pEMRDG3NFLa7OxVZhNfIoHIUtgS2LEo2RrOGuGWHUh2oaTsSxYHqOvRKkJsRLJlpGhIQBXEFcMoUmozaJxdlqFdN5MIvsFVEsCopJb9BsyohWZz19r2KHwEinNnW2A91uF6Fhb0TaZbVH+Ovq7u0LVXH3nMrfAOIjcEewkSIbSJRIkRnuMqb6wVFjIWLfjSe2OZh1vN0mMpwJF0EsYMjvT2z8/TCFfuCYIjEqcu2UCoFfmjP1JngXtuvkiUoQYgdwXcDJgT2mLesp4teM0+Vys1o0wGap4pq0cVTFAADW5wYr0K68elvH6uLBScUah+zjJ0J7L4hJGawZPfebJAEI9xQT88gQSMxmS7CSJXZ8jIzBkvLwRrQNpce4M5LyMMbXwlcYKqzweUSgHXPACrrDIQzBWQi1LJxiW+TjZcMlIbCMveeUhbM4kzEXYufrPlORm7lgeK59Z67XxOYCgjs92woG1YsATzNE7m1ZaMYM5kJ1JU6ZdIoAAk3HzQGFhhJYMOIBkF255KA4FQ1fBRRtmIstoobPW3tFkK/ZVkmDoXQhIWycEdKRZAostzKns6VtIJhW7ZVG7KZOkcBAUDW5HurCQ4bvGZ8YwSN7DhjP4a1gVFFbpWJK0U+xxWJeQHPbjss1pwvNV6AYUdFmtDfpnqNpVy8QMb5ekLI3Qr5ulGoJG7SrRUtuyr3XJFVwlAfZDnr92nc7SwN48KK26fowPtk27z2NuWRc8n9Wx4fhB//RD9NvFVh7Ma1lEJ56q2OwCHqmAsDM7kMKYIFPLObqrPPOddi7ZYi0KAtTi2gZWToX7SDNjb0p9hZPUM/JUTw4AqCjODnRUdpf1gIGSo3VdWX6bb8JM2rDywxbrR0DMmqLGr8y+Q2cRLnrJC85xkICaJePjA2AX+seiYVS7I1oPWU0smy5XQVdyTflBlLcjg+Lht2UlaQdroNut3DgRDQKHDGQrUi4ATgltOPyGRLCviuNJ5aaozSmuO0gPi1lqkbYcEpR4boY9hpptiSU1dmNZhS2Bt/aRAORZPCpgPaEdXQqnrJUk/Zu9O63sMRIBNya9iziob8IdA+WXySSUmKp/0sCPf9mcE2QIXW+nvvDdk+s2bl4vLSNfU10LCJLguh7NR4iqCkpEtatuRgjfODV00jBioLYdqIYFz1agn0v655zOMgOA9J4tgcciRQnRQNyr7H5AuwsEoyubgIa6nyIjGyGELpEWx5AipFN+aRJadwqBVglRp5t8/9w45osYqpMs0K/4ih3UhLUwU592YOU8zPAaB0aKwlMWQaUlRY4rKjs/SVh1ASrlFpaBArZPDvdFr8nLm0jXXivuIU3pAmVPzEZMZQXm3FQ7t2AVNgqtTlaoP5EJO98hronhd83mOuzLVdzeg3M4KLcsPm+R0kc/6Dmgu2aGN0EINdcuhq1jLtdkpKmSBy7+Vg5n5krK+WGXh6VOddNNZhRltFjnltcdNOlI4M60aQJhDNHxqvtnRaTX1Jq/TmeWbzVoFDUvVBt67NAZKTFnShRhwyJKh7T60k6SiYKRKOTnx5e9AZDx5zBtbPMhtVoJq4ast5Jn9QHRGiSK0MsU5tJnjZnTu3yJzdWfcGkdt4u1iSRX2Z3wHygbCyju6wG3mxxfs7T2tuA7tVPN2UpI2V4VrJKw7kA0O7Nc7q0vuniOuFBRiaGNdx8dy7xLQ2f9yz/4vp7T+/Gn0Jy3l24NJBzx/gh78kzRy/nBsEA5+6OKb14js9h85K5ywtMapdzHf2/9H9DDtLkM26h3ISl5tyPnXPOp0B4lrrWmig+J3iaT9G6bzkPGB28wXabuIxqfqvZdB6NjVv3t/Mu6dz6NyvtV27x761127unL+Tdf4hl7V+z9McMWLjGqdI974ZxxeBq1Z3dZM79579pThvkbtcw3MafZu0eA9F6PQg%]]),
	portal_open = Nya.load_sound([[ROK_I1AAP5|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]]),
	portal_reset = Nya.load_sound([[ROK_I1AAWD|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$]]),
	pick_up_cube = Nya.load_sound([[ROK_M1AAWH|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]]),

}

local pcl = false
function TIC()
	cls(15)
	print("Nya audio engine By HanamileH", 1, 130, 0)
	print("Nya audio engine By HanamileH", 1, 129, 12)

	local mx, my, cl = mouse()

	local y = 0
	for k, v in pairs(sounds) do
		local selected = (my > y * 8) and (my - 8 <= y * 8)

		print(k, 1, y * 8 + 1, selected and 12 or 13)

		if selected and cl and not pcl then
			Nya.play(v)
		end

		y = y + 1
	end

	Nya.update()

	pcl = cl
end

-- <TILES>
-- 001:eccccccccc888888caaaaaaaca888888cacccccccacc0ccccacc0ccccacc0ccc
-- 002:ccccceee8888cceeaaaa0cee888a0ceeccca0ccc0cca0c0c0cca0c0c0cca0c0c
-- 003:eccccccccc888888caaaaaaaca888888cacccccccacccccccacc0ccccacc0ccc
-- 004:ccccceee8888cceeaaaa0cee888a0ceeccca0cccccca0c0c0cca0c0c0cca0c0c
-- 017:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 018:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- 019:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 020:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- </TILES>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000304000000000
-- </SFX>

-- <TRACKS>
-- 000:100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

