using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace OKCodec
{
    internal static class Program
    {
        // ------------------------------------------------------------------
        //  Format constants (locked by the OKcodec spec)
        // ------------------------------------------------------------------

        // The output sample rate is fixed; the header does not store it.
        private const int FixedSampleRate = 7680;

        // The LZW dictionary is initialised with the 16 hex digits.
        private const string HexChars = "0123456789abcdef";

        // ------------------------------------------------------------------
        //  Runtime configuration (overridable from the command line)
        // ------------------------------------------------------------------
        private sealed class Config
        {
            public int AudioDepth = 2;   // 1..4, quantization depth of audio samples
            public int RangeDepth = 4;   // 1..4, quantization depth of chunk min/max
            public int ChunkSize  = 32;  // power of two in [16, 128]
            public string InputPath;
            public string OutputPath;
        }

        // ==================================================================
        //  Entry point
        // ==================================================================
        private static int Main(string[] args)
        {
            try
            {
                if (!TryParseArgs(args, out Config cfg))
                    return 0; // help was printed or no arguments provided

                Run(cfg);
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Error: " + ex.Message);
                Console.Error.WriteLine("Try 'okcodec --help' for usage.");
                return 1;
            }
        }

        // ==================================================================
        //  Command-line parsing
        // ==================================================================
        private static bool TryParseArgs(string[] args, out Config cfg)
        {
            cfg = null;

            if (args.Length == 0)
            {
                PrintHelp();
                return false;
            }

            var c = new Config();
            var positional = new List<string>();

            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                switch (a)
                {
                    case "-h":
                    case "--help":
                        PrintHelp();
                        return false;

                    case "-a":
                    case "--audio-depth":
                        c.AudioDepth = ParseInt(NextArg(args, ref i, a), a);
                        break;

                    case "-r":
                    case "--range-depth":
                        c.RangeDepth = ParseInt(NextArg(args, ref i, a), a);
                        break;

                    case "-c":
                    case "--chunk-size":
                        c.ChunkSize = ParseInt(NextArg(args, ref i, a), a);
                        break;

                    default:
                        if (a.StartsWith("-") && a.Length > 1)
                            throw new ArgumentException($"Unknown option: {a}");
                        positional.Add(a);
                        break;
                }
            }

            if (positional.Count != 2)
                throw new ArgumentException("Expected exactly two positional arguments: <input> <output>");

            // Depth is limited to 4 because each delta value must fit in a single hex digit.
            if (c.AudioDepth < 1 || c.AudioDepth > 4)
                throw new ArgumentException("--audio-depth must be in range 1..4");
            if (c.RangeDepth < 1 || c.RangeDepth > 4)
                throw new ArgumentException("--range-depth must be in range 1..4");

            // Chunk size must be a power of two within [16, 128].
            if (c.ChunkSize < 16 || c.ChunkSize > 128 || (c.ChunkSize & (c.ChunkSize - 1)) != 0)
                throw new ArgumentException("--chunk-size must be a power of two in [16, 128]");

            c.InputPath  = positional[0];
            c.OutputPath = positional[1];

            if (!File.Exists(c.InputPath))
                throw new FileNotFoundException($"Input file not found: {c.InputPath}");

            cfg = c;
            return true;
        }

        private static string NextArg(string[] args, ref int i, string flag)
        {
            if (i + 1 >= args.Length)
                throw new ArgumentException($"Option {flag} requires a value");
            return args[++i];
        }

        private static int ParseInt(string s, string flag)
        {
            if (!int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out int v))
                throw new ArgumentException($"Option {flag} expects an integer, got '{s}'");
            return v;
        }

        private static void PrintHelp()
        {
            Console.WriteLine(
@"Okcodec - audio converter for the (Reasonably) OKCodec compressed audio format.

Usage:
  okcodec [options] <input> <output>

Arguments:
  <input>              Input audio file (wav, mp3, aiff, ...).
  <output>             Output text file (Lua module with 'local audio = [[...]]').

Options:
  -h, --help           Show this help message and exit.
  -a, --audio-depth N  Quantization depth of audio samples, 1..4.
                       Higher = better quality, larger file. Default: 2.
  -r, --range-depth N  Quantization depth of chunk min/max values, 1..4.
                       Default: 4.
  -c, --chunk-size  N  Samples per chunk; power of two in [16, 128].
                       Default: 32.

Examples:
  okcodec music.wav Compressed.txt
  okcodec -a 3 -c 64 speech.mp3 out.txt
");
        }

        // ==================================================================
        //  Main pipeline
        // ==================================================================
        private static void Run(Config cfg)
        {
            // 1) Load and resample input audio to the fixed sample rate.
            float[] raw = LoadAudio(cfg.InputPath);

            // 2) Trim, normalize, quantize and delta-encode.
            var (audioData, maxsData, minsData, usedSamples) = ProcessAudio(raw, cfg);

            // 3) Serialize both streams as hex strings.
            string volumeHex = BuildHexPair(maxsData, minsData);
            string waveHex   = BuildHexSingle(audioData);

            // 4) LZW-compress each stream separately.
            string compressed1 = LzwCompress(volumeHex);
            string compressed2 = LzwCompress(waveHex);

            // 5) Assemble the final Lua module.
            string header       = MakeHeader(compressed1.Length, cfg);
            string body         = B64Encode(compressed1 + compressed2);
            string fileContents = $"local audio = [[{header}|{body}]]\n";

            File.WriteAllText(cfg.OutputPath, fileContents, new UTF8Encoding(false));

            // 6) Print summary.
            PrintReport(cfg, usedSamples, body.Length, fileContents);
        }

        // ==================================================================
        //  Statistics report
        // ==================================================================
        private static void PrintReport(Config cfg, int usedSamples, int bodyChars, string fileContents)
        {
            double durationSec = usedSamples / (double)FixedSampleRate;

            // 1 base64 character carries 6 bits.
            long bodyBits  = (long)bodyChars * 6L;
            long bodyBytes = bodyBits / 8L;

            long fileChars = fileContents.Length;
            long fileBytes = Encoding.UTF8.GetByteCount(fileContents);

            double bitrateKbps = durationSec > 0.0
                ? bodyBits / 8.0 / durationSec / 1000.0
                : 0.0;

            Console.WriteLine($"Format     : audio-depth={cfg.AudioDepth}, range-depth={cfg.RangeDepth}, chunk-size={cfg.ChunkSize}");
            Console.WriteLine($"Sample rate: {FixedSampleRate} Hz");
            Console.WriteLine($"Duration   : {durationSec:F3} s ({usedSamples} samples)");
            Console.WriteLine($"File size  : {fileChars} chars / {fileBytes} bytes ({fileBytes / 1024.0:F2} KB)");
            Console.WriteLine($"Bitrate    : {bitrateKbps:F2} Kbps");
        }

        // ==================================================================
        //  Audio loading / resampling
        // ==================================================================
        private static float[] LoadAudio(string path)
        {
            using var reader = new AudioFileReader(path);
            ISampleProvider provider = reader.ToSampleProvider();

            // Down-mix to mono.
            if (provider.WaveFormat.Channels == 2)
                provider = new StereoToMonoSampleProvider(provider);

            // Resample to the fixed target rate.
            if (provider.WaveFormat.SampleRate != FixedSampleRate)
                provider = new WdlResamplingSampleProvider(provider, FixedSampleRate);

            var samples = new List<float>(1 << 16);
            var buffer  = new float[8192];
            int read;
            while ((read = provider.Read(buffer, 0, buffer.Length)) > 0)
                for (int i = 0; i < read; i++) samples.Add(buffer[i]);

            return samples.ToArray();
        }

        // ==================================================================
        //  ProcessAudio - port of processAudio() from main.py
        // ==================================================================
        private static (int[] audio, int[] maxs, int[] mins, int usedSamples)
            ProcessAudio(float[] input, Config cfg)
        {
            // 1) Trim leading/trailing silence.
            int start = 0;
            while (start < input.Length && input[start] == 0f) start++;
            int end = input.Length - 1;
            while (end >= start && input[end] == 0f) end--;

            if (start > end)
                return (Array.Empty<int>(), Array.Empty<int>(), Array.Empty<int>(), 0);

            int len = end - start + 1;
            var audio = new float[len];
            Array.Copy(input, start, audio, 0, len);

            // 2) Peak normalisation.
            float maxAbs = 0f;
            for (int i = 0; i < len; i++)
            {
                float a = Math.Abs(audio[i]);
                if (a > maxAbs) maxAbs = a;
            }
            if (maxAbs > 0f)
                for (int i = 0; i < len; i++) audio[i] /= maxAbs;

            // 3) Pad to a multiple of chunk size.
            int remainder = len % cfg.ChunkSize;
            if (remainder != 0)
            {
                int padLen = cfg.ChunkSize - remainder;
                var padded = new float[len + padLen];
                Array.Copy(audio, padded, len);
                audio = padded;
            }

            int numChunks = audio.Length / cfg.ChunkSize;

            int maxAudioCode = (1 << cfg.AudioDepth) - 1;
            int maxRangeCode = (1 << cfg.RangeDepth) - 1;

            var audioData = new int[audio.Length];
            var maxsData  = new int[numChunks];
            var minsData  = new int[numChunks];

            for (int c = 0; c < numChunks; c++)
            {
                int baseIdx = c * cfg.ChunkSize;

                // Find the min/max inside this chunk.
                float mx = float.MinValue, mn = float.MaxValue;
                for (int j = 0; j < cfg.ChunkSize; j++)
                {
                    float v = audio[baseIdx + j];
                    if (v > mx) mx = v;
                    if (v < mn) mn = v;
                }

                float width = mx - mn;
                if (width < 1e-5f) width = 1e-5f;

                // Normalise each sample within the chunk, then quantise it.
                for (int j = 0; j < cfg.ChunkSize; j++)
                {
                    float normalized = (audio[baseIdx + j] - mn) / width;
                    int q = (int)Math.Round(normalized * maxAudioCode);
                    if (q < 0) q = 0;
                    if (q > maxAudioCode) q = maxAudioCode;
                    audioData[baseIdx + j] = q;
                }

                // Quantise chunk min/max from [-1, 1] to [0, maxRangeCode].
                maxsData[c] = QuantizeRange(mx, maxRangeCode);
                minsData[c] = QuantizeRange(mn, maxRangeCode);
            }

            // 4) Delta-encode with wraparound modulo the code range.
            audioData = DeltaEncode(audioData, 1 << cfg.AudioDepth);
            maxsData  = DeltaEncode(maxsData,  1 << cfg.RangeDepth);
            minsData  = DeltaEncode(minsData,  1 << cfg.RangeDepth);

            return (audioData, maxsData, minsData, len);
        }

        // Maps a value from [-1, 1] to the integer range [0, maxCode].
        private static int QuantizeRange(float v, int maxCode)
        {
            float shifted = v * 0.5f + 0.5f;
            int q = (int)Math.Round(shifted * maxCode);
            if (q < 0) q = 0;
            if (q > maxCode) q = maxCode;
            return q;
        }

        // Delta encoding; negative differences wrap around by adding `mod`.
        private static int[] DeltaEncode(int[] data, int mod)
        {
            if (data.Length == 0) return data;
            var result = new int[data.Length];
            result[0] = data[0];
            for (int i = 1; i < data.Length; i++)
            {
                int d = data[i] - data[i - 1];
                if (d < 0) d += mod;
                result[i] = d;
            }
            return result;
        }

        // ==================================================================
        //  Hex serialization (single-char per value, values must be 0..15)
        // ==================================================================
        private static string BuildHexSingle(int[] values)
        {
            var sb = new StringBuilder(values.Length);
            for (int i = 0; i < values.Length; i++)
                sb.Append(HexChars[values[i]]);
            return sb.ToString();
        }

        private static string BuildHexPair(int[] a, int[] b)
        {
            var sb = new StringBuilder(a.Length * 2);
            for (int i = 0; i < a.Length; i++)
            {
                sb.Append(HexChars[a[i]]);
                sb.Append(HexChars[b[i]]);
            }
            return sb.ToString();
        }

        // ==================================================================
        //  LZW compression
        // ==================================================================

        // The LZW alphabet is the 16 hex characters, so the initial dictionary
        // size is fixed regardless of the audio/range depth chosen above.
        private static string LzwCompress(string input)
        {
            if (string.IsNullOrEmpty(input)) return string.Empty;

            // Map every hex character to its initial code (0..15).
            var charMap = new int[128];
            for (int i = 0; i < 16; i++) charMap[HexChars[i]] = i;

            // transitions[(prefixCode << 4) | nextCharCode] = newCode
            var transitions = new Dictionary<int, int>(1 << 16);

            int nextFree       = 16;         // codes 0..15 already used
            int indexSize      = 4;          // ceil(log2(16)) = 4
            int smallIndexSize = indexSize - 1;

            var output = new StringBuilder();

            int pCode = charMap[input[0]];

            for (int i = 1; i < input.Length; i++)
            {
                int cIdx = charMap[input[i]];
                int key  = (pCode << 4) | cIdx;

                if (transitions.TryGetValue(key, out int existing))
                {
                    // Extend the current prefix.
                    pCode = existing;
                }
                else
                {
                    // Emit the prefix code, then add the new combination.
                    WriteIndex(output, pCode, smallIndexSize, indexSize);
                    transitions[key] = nextFree++;
                    pCode = cIdx;

                    // Grow the long index width once the current one is exhausted.
                    if ((nextFree & (nextFree - 1)) == 0)
                        indexSize++;

                    // Grow the short index width once 75% of the range is used.
                    if ((1 << (indexSize - 1)) * 3 == nextFree - 1)
                        smallIndexSize++;
                }
            }

            // Flush the last prefix.
            WriteIndex(output, pCode, smallIndexSize, indexSize);
            return output.ToString();
        }

        // Emit one code using the "short/long" flag scheme.
        private static void WriteIndex(StringBuilder sb, int index, int smallIndexSize, int indexSize)
        {
            if ((index >> smallIndexSize) == 0)
            {
                sb.Append('0');
                AppendBits(sb, index, smallIndexSize);
            }
            else
            {
                sb.Append('1');
                AppendBits(sb, index - (1 << smallIndexSize), indexSize);
            }
        }

        private static void AppendBits(StringBuilder sb, int value, int count)
        {
            for (int i = count - 1; i >= 0; i--)
                sb.Append(((value >> i) & 1) != 0 ? '1' : '0');
        }

        // ==================================================================
        //  OKCodec header
        // ==================================================================
        private static string MakeHeader(int firstFragmentSize, Config cfg)
        {
            var bits = new StringBuilder(36);
            AppendFixedBits(bits, cfg.AudioDepth - 1, 4);   // 4 bits: 0..15
            AppendFixedBits(bits, cfg.RangeDepth - 1, 4);   // 4 bits: 0..15
            AppendFixedBits(bits, (int)Math.Log(cfg.ChunkSize, 2), 4); // 4 bits: log2(chunk)
            AppendFixedBits(bits, firstFragmentSize, 24);   // 24 bits: size of first fragment
            return "ROK_" + B64Encode(bits.ToString());
        }

        private static void AppendFixedBits(StringBuilder sb, int value, int count)
        {
            for (int i = count - 1; i >= 0; i--)
                sb.Append(((value >> i) & 1) != 0 ? '1' : '0');
        }

        // ==================================================================
        //  Custom base64 (6-bit groups + remainder marker)
        //  This is NOT standard RFC 4648 base64
        //    - 6 bits of input become one output character
        //    - the last incomplete group is padded with zero bits
        //    - the number of significant bits (1..5) is appended using
        //      the '#' '$' '%' '&' '=' characters.
        // ==================================================================
        private static string B64Encode(string data)
        {
            const string alphabet       = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            const string remainderChars = "#$%&=";

            int l1 = data.Length;
            int paddedLen = (l1 % 6 == 0) ? l1 : l1 + (6 - l1 % 6);

            var result = new StringBuilder(paddedLen / 6 + 1);

            for (int i = 0; i < paddedLen; i += 6)
            {
                int val = 0;
                for (int j = 0; j < 6; j++)
                {
                    val <<= 1;
                    int idx = i + j;
                    if (idx < l1 && data[idx] == '1') val |= 1;
                }
                result.Append(alphabet[val]);
            }

            // Append the remainder marker for the last partial group.
            if (l1 % 6 > 0)
                result.Append(remainderChars[l1 % 6 - 1]);

            return result.ToString();
        }
    }
}
