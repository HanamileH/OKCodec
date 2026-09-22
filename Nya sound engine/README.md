# Nya sound engine
Nya sound engine is a PCM sound engine for TIC-80, designed for playing OKCodec audio, written in Lua.

---

## Installation
1. Copy the `main.lua` code into your TIC-80 project
2. Load your compressed audio into the project
3. Use the `Nya.play` function to add audio to the playback queue
4. Use the `Nya.update` function in the main loop (`TIC`) to update the engine state

---

## API
### Nya.play
`Nya.play(sound, loop, volume)`
Function for adding audio to the playback queue.

#### Parameters
- `sound` - the audio data to play
- `loop` - flag indicating whether the audio should be looped (default: `false`)
- `volume` - volume level (from 0 to 1) (default: 1)

#### Returns
- `sound_id` - identifier of the added audio

<br>

### Nya.stop
`Nya.stop(sound_id)`
Function for stopping audio playback.

#### Parameters
- `sound_id` - identifier of the audio to stop

<br>

### Nya.is_alive
`Nya.is_alive(sound_id)`
Function for checking whether audio is playing.

#### Parameters
- `sound_id` - identifier of the audio to check

#### Returns
- `true` or `false` depending on whether the audio is playing

<br>

### Nya.load_sound
`Nya.load_sound(data)`
Function for loading audio data.

#### Parameters
- `data` - the audio data to load (in base64 format, obtained from OKCodec)

#### Returns
- `sound_data` - audio data table that can be used in the `Nya.play` function

<br>

### Nya.update
`Nya.update()`
Function for updating the engine state. Must be called in the main loop (`TIC`).

---

## Demonstration
The `demo.lua` file contains a demonstration of the engine. This project has several audio tracks that can be played by clicking on their name.
Load it into TIC-80 and run it to hear audio playback.

The files `a2.lua`, `a3.lua`, and `a4.lua` in the `/quality` folder contain versions of the audio with different quality levels. Load them into TIC-80 and run them to hear the difference in sound quality.

---

## License
This project is distributed under the `MIT license`; see the `LICENSE` file for details.