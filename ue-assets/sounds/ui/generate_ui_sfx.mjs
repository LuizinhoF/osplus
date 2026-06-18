import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const sampleRate = 48000;
const outDir = path.dirname(fileURLToPath(import.meta.url));
let seed = 20260618;

function rand() {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 0x100000000;
}

function sine(freq, t) {
  return Math.sin(2 * Math.PI * freq * t);
}

function env(t, attack, hold, release, dur) {
  if (t < attack) return t / Math.max(attack, 1e-6);
  if (t < attack + hold) return 1;
  const x = (t - attack - hold) / Math.max(dur - attack - hold, 1e-6);
  return Math.max(0, (1 - x) * (1 - x));
}

function softClip(x) {
  return Math.tanh(1.1 * x) / Math.tanh(1.1);
}

function lowpass(samples, cutoffHz) {
  const alpha = 1 - Math.exp((-2 * Math.PI * cutoffHz) / sampleRate);
  let y = 0;
  return samples.map((x) => {
    y += alpha * (x - y);
    return y;
  });
}

function highpass(samples, cutoffHz) {
  const rc = 1 / (2 * Math.PI * cutoffHz);
  const dt = 1 / sampleRate;
  const alpha = rc / (rc + dt);
  let y = 0;
  let lastX = 0;
  return samples.map((x) => {
    y = alpha * (y + x - lastX);
    lastX = x;
    return y;
  });
}

function chirp(startFreq, endFreq, t, duration) {
  const x = Math.max(0, Math.min(1, t / duration));
  const freq = startFreq + (endFreq - startFreq) * x;
  return sine(freq, t);
}

function writeWav(filePath, samples) {
  const dataBytes = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataBytes);
  buffer.write("RIFF", 0);
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write("WAVE", 8);
  buffer.write("fmt ", 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36);
  buffer.writeUInt32LE(dataBytes, 40);

  for (let i = 0; i < samples.length; i += 1) {
    const value = Math.max(-1, Math.min(1, samples[i]));
    buffer.writeInt16LE(Math.round(value * 32767), 44 + i * 2);
  }

  fs.writeFileSync(filePath, buffer);
}

function render({ name, duration, peak, highpass: highpassHz = 0, cutoff, synth }) {
  const frameCount = Math.floor(sampleRate * duration);
  let samples = Array.from({ length: frameCount }, (_, i) => {
    const t = i / sampleRate;
    const edge = Math.min(
      1,
      i / Math.max(1, Math.floor(0.007 * sampleRate)),
      (frameCount - 1 - i) / Math.max(1, Math.floor(0.014 * sampleRate)),
    );
    return synth(t, duration) * Math.max(0, edge);
  });

  if (highpassHz > 0) {
    samples = highpass(samples, highpassHz);
  }
  samples = lowpass(samples, cutoff).map(softClip);

  const currentPeak = samples.reduce((max, sample) => Math.max(max, Math.abs(sample)), 0) || 1;
  const gain = peak / currentPeak;
  samples = samples.map((sample) => sample * gain);

  const filePath = path.join(outDir, `${name}.wav`);
  writeWav(filePath, samples);

  const rms = Math.sqrt(samples.reduce((sum, sample) => sum + sample * sample, 0) / samples.length);
  return {
    name,
    durationMs: Math.round(duration * 1000),
    peak,
    rms: Number(rms.toFixed(4)),
    highpass: highpassHz,
    cutoff,
  };
}

const specs = [
  {
    name: "SFX_OSPlus_UI_Hover",
    duration: 0.034,
    peak: 0.14,
    highpass: 260,
    cutoff: 3600,
    synth(t, duration) {
      const e = env(t, 0.004, 0.000, 0.030, duration);
      const tick = 0.34 * chirp(1180, 1480, t, duration) + 0.13 * sine(2360, t);
      const plastic = (rand() * 2 - 1) * 0.016;
      return e * (tick + plastic);
    },
  },
  {
    name: "SFX_OSPlus_UI_Click",
    duration: 0.074,
    peak: 0.40,
    highpass: 180,
    cutoff: 3900,
    synth(t, duration) {
      const pop = env(t, 0.003, 0.002, 0.069, duration) * (0.32 * sine(720, t) + 0.18 * sine(1080, t));
      const snap = t >= 0.010
        ? env(t - 0.010, 0.003, 0.000, 0.061, duration - 0.010) * (0.26 * sine(1560, t) + 0.11 * sine(2340, t))
        : 0;
      const air = (rand() * 2 - 1) * 0.020 * env(t, 0.002, 0.000, 0.072, duration);
      return pop + snap + air;
    },
  },
  {
    name: "SFX_OSPlus_UI_Open",
    duration: 0.124,
    peak: 0.45,
    highpass: 220,
    cutoff: 4300,
    synth(t, duration) {
      const e = env(t, 0.010, 0.006, 0.108, duration);
      const body = 0.40 * chirp(780, 1160, t, duration) + 0.18 * chirp(1170, 1740, t, duration);
      const zip = (rand() * 2 - 1) * 0.035 * env(t, 0.004, 0.000, 0.120, duration);
      const late = t > 0.046
        ? env(t - 0.046, 0.006, 0.000, 0.072, duration - 0.046) * 0.20 * sine(1760, t)
        : 0;
      return e * (body + zip) + late;
    },
  },
  {
    name: "SFX_OSPlus_UI_Equip",
    duration: 0.118,
    peak: 0.46,
    highpass: 300,
    cutoff: 5200,
    synth(t, duration) {
      const snap = env(t, 0.002, 0.000, 0.036, duration)
        * (0.20 * chirp(1080, 820, t, 0.040) + 0.11 * sine(1640, t));
      const lift = t > 0.024
        ? env(t - 0.024, 0.004, 0.000, 0.056, duration - 0.024)
          * (0.24 * chirp(1120, 1580, t - 0.024, 0.060) + 0.10 * sine(2240, t))
        : 0;
      const shine = t > 0.068
        ? env(t - 0.068, 0.003, 0.000, 0.044, duration - 0.068)
          * (0.11 * chirp(1840, 2460, t - 0.068, 0.046) + 0.04 * sine(3280, t))
        : 0;
      const air = (rand() * 2 - 1) * 0.018 * env(t, 0.001, 0.000, 0.048, duration);
      return snap + lift + shine + air;
    },
  },
];

console.log(JSON.stringify(specs.map(render), null, 2));
