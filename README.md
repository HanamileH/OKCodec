# (Reasonable) OKCodec
(Reasonable) OKCodec is an audio codec designed for TIC-80 PCM. This codec was created with a focus on minimum file size while maintaining reasonably good audio quality.
At an average quality level, this codec allows achieving `1.7 kbps` (`2.27 kbps` when encoded in base64).
This corresponds to a maximum audio length of `3 minutes 45 seconds` when using `524288 characters` for recording (the maximum code size for TIC-80 Pro).

---

## Is it really that good?
More yes than no. Of course, it is best to compare this side-by-side with what TIC-80 PCM can provide under ideal conditions, but to my subjective hearing, this algorithm will probably be good enough to notice the difference.
Does it sound bad? Of course not. At standard compression settings, the audio sounds intelligible enough to use for voice-over, sound effects, or a simple soundtrack. And if you increase the quality settings, it will be good enough for almost any song.
Again, this codec was not created with the goal of minimizing the audible difference between the compressed and original file.
The goal was to reduce file size to a minimum while keeping quality at an acceptable level that hardly anyone would complain about.

---

## Quick start
1. Download the CLI conversion tool (use the source code from the `OKCodec` folder, or the built tool from the release page)
2. Run `okcodec input.mp3 result.txt` to convert audio; optionally add compression parameters (see parameters below)
3. Copy the contents of `result.txt` into your TIC-80 cartridge
4. Use the code from the `Nya audio engine` folder to play audio in TIC-80

---

## Parameters
Usage: `okcodec [options] <input> <output>`

| Flag | Full flag | Default | Description |
|------|-------------|--------------|----------|
| `-h` | `--help` | - | Print help information |
| `-a` | `--audio-depth` | `2` | Audio depth quality inside a chunk (range `1..4`), higher is better quality |
| `-r` | `--range-depth` | `4` | Range depth quality of a chunk (range `1..4`), higher is better quality |
| `-c` | `--chunk-size` | `32` | Size of one chunk (power of two in range `16..128`), lower is better quality |
| | `<input>` | - | Input audio file |
| | `<output>` | - | Output file (`.txt` or `.lua` recommended) |

<br>

### Parameter description
**Audio depth** is the sampling depth for storing the actual sound wave inside one chunk.
A high value allows getting rid of noise caused by the compression algorithm.
If your goal is to get excellent quality, it is recommended to change this parameter first.
- **4 bits (16 values)** provides the best possible quality, but takes up more space;
- **3 bits (8 values)** takes up less space while providing excellent quality (recommended if at 2 bits there is unpleasant compression noise);
- **2 bits (4 values)** a reasonable compromise between size and quality, recommended as the default value;
- **1 bit (2 values)** probably not worth using.

<br>

**Range depth** is the sampling depth of the range of the maximum and minimum value of one block.
Probably the value `4 bit` is the most reasonable, but you can play with this parameter if you need to reduce audio size.

<br>

**Chunk size** is the number of samples per chunk.
High values provide strong compression, but can create artifacts at the boundary of quiet and loud sections.
If you need to reduce file size, it is recommended to increase this value.
Usually, the best practice is to select the value manually for each audio depending on your size and quality requirements.

---

## License
This project is distributed under the `MIT license`; see the `LICENSE` file for details.