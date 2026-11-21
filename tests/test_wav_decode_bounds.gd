extends "res://tests/suite.gd"

func run() -> Array[String]:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 16000
	wav.data = PackedByteArray([0, 0, 1, 0, 255, 127, 0, 128])
	var body := NaretUniAPIClient.encode_wav(wav)
	var decoded := NaretUniAPIClient.decode_audio(body) as AudioStreamWAV
	check(decoded != null and decoded.data == wav.data, "ordinary PCM audio preserves samples")
	var streaming := body.duplicate()
	streaming.encode_u32(4, 0xffffffff)
	streaming.encode_u32(40, 0xffffffff)
	decoded = NaretUniAPIClient.decode_audio(streaming) as AudioStreamWAV
	check(decoded != null and decoded.data == wav.data, "streaming lengths are bounded by HTTP body")
	var truncated := body.slice(0, body.size() - 1)
	check(NaretUniAPIClient.decode_audio(truncated) == null, "truncated payload rejected without native parser")
	var bad_chunk := body.duplicate()
	bad_chunk.encode_u32(16, 0xffffffff)
	check(NaretUniAPIClient.decode_audio(bad_chunk) == null, "oversized fmt rejected")
	var zero_chunk := "RIFF".to_ascii_buffer()
	zero_chunk.append_array(PackedByteArray([12,0,0,0]))
	zero_chunk.append_array("WAVEJUNK".to_ascii_buffer())
	zero_chunk.append_array(PackedByteArray([0,0,0,0]))
	check(NaretUniAPIClient.decode_audio(zero_chunk) == null, "empty chunk terminates")
	var unsupported := body.duplicate()
	unsupported.encode_u16(20, 3)
	check(NaretUniAPIClient.decode_audio(unsupported) == null, "unsupported audio falls back safely")
	return failures
