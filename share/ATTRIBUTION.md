# share/

## `cash-register.wav`

Cash register sound, played by `bin/cc-cost-tick` at the end of every turn that costs something.

- Source: <https://www.free-stock-music.com/sound-effects-library-cash-register-sound.html>
- Author: Sound Effects Library
- Licence: CC0 1.0 Universal (public domain dedication) — no attribution required, given here anyway.

The original is a 2.43s stereo MP3. What ships here was prepared for use as a per-turn notification:

```
ffmpeg -i sound-effects-library-cash-register-sound.mp3 \
  -ac 1 -ar 44100 \
  -af "atrim=0:1.4,asetpts=N/SR/TB,afade=t=out:st=1.34:d=0.06,volume=0.504" \
  -c:a pcm_s16le cash-register.wav
```

Mono, because a notification does not need a stereo field. Trimmed at 1.4s — everything past it sits
below -34 dBFS and decays to nothing, so it was 0.9s of silence in every commit and every play. Faded
over the last 60ms so the cut lands on a zero rather than a click. Levelled to a -6 dBFS peak,
because the original is normalised to full scale and full scale several times an hour is punishing.

Replace it with `RTC_SOUND=/path/to.wav`, or silence it with `RTC_MUTE=1`.
