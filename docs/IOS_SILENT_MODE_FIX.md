# iOS Silent Mode Bypass - Technical Documentation

## The Problem

iOS Safari respects the physical mute switch (Silent Mode) for web audio by default. When the mute switch is on, audio from `AudioContext.destination` is silenced.

This is because iOS categorizes Web Audio API output as "ambient" audio, which respects the mute switch.

## The Solution

Route audio through an HTML5 `<audio>` element instead of directly to `audioContext.destination`. iOS treats `<audio>` elements as "media playback" which **ignores the mute switch**.

## How It Works

### Before (Doesn't work in silent mode):
```
ScriptProcessorNode → GainNode → audioContext.destination
```

### After (Works in silent mode):
```
ScriptProcessorNode → GainNode → MediaStreamDestination → <audio> element
```

## Implementation

### 1. HTML - Add hidden audio element
```html
<audio id="outputAudio" playsinline style="display:none"></audio>
```

### 2. JavaScript - Create MediaStreamDestination
```javascript
// Create MediaStream destination instead of using audioContext.destination
const mediaStreamDest = audioContext.createMediaStreamDestination();

// Connect your audio processing chain to the MediaStream
gainNode.connect(mediaStreamDest);  // NOT audioContext.destination

// Route the MediaStream through the HTML5 audio element
const outputAudio = document.getElementById('outputAudio');
outputAudio.srcObject = mediaStreamDest.stream;
outputAudio.play();
```

### 3. Complete Audio Chain
```javascript
// Create nodes
const audioContext = new AudioContext();
const mediaStreamDest = audioContext.createMediaStreamDestination();
const gainNode = audioContext.createGain();
const scriptNode = audioContext.createScriptProcessor(512, 0, 2);

// Connect chain
scriptNode.connect(gainNode);
gainNode.connect(mediaStreamDest);  // Key: connect to MediaStream, not destination

// Route through audio element
const outputAudio = document.getElementById('outputAudio');
outputAudio.srcObject = mediaStreamDest.stream;
outputAudio.play();
```

## Why This Works

1. **AudioContext.destination** → iOS categorizes as "ambient" → respects mute switch
2. **HTML5 `<audio>` element** → iOS categorizes as "playback" → ignores mute switch

By routing Web Audio through a MediaStreamDestination and connecting that stream to an `<audio>` element, we trick iOS into treating our audio as media playback.

## Reference

This same technique is used on https://cymatics.fm for audio playback that works regardless of iOS silent mode status.

## Key Points

- The `<audio>` element must have `playsinline` attribute for iOS
- The element can be hidden with `display:none`
- Must call `.play()` on the audio element (requires user gesture)
- The `srcObject` property connects the MediaStream to the audio element

## Cleanup

When stopping audio:
```javascript
const outputAudio = document.getElementById('outputAudio');
outputAudio.pause();
outputAudio.srcObject = null;
```

