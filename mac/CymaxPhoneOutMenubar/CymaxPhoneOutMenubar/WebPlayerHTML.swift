//
//  WebPlayerHTML.swift
//  CymaxPhoneOutMenubar
//
//  Embedded HTML/JS for the web audio player
//

import Foundation

/// Returns the HTML content for the web audio player
/// - Parameter wsPort: WebSocket port to connect to
/// - Parameter hostIP: IP address of the Mac
func getWebPlayerHTML(wsPort: UInt16, hostIP: String) -> String {
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Cymax Audio</title>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: #fff;
            padding: 20px;
        }
        
        .container {
            text-align: center;
            max-width: 400px;
            width: 100%;
        }
        
        h1 {
            font-size: 1.8rem;
            margin-bottom: 8px;
            font-weight: 600;
        }
        
        .subtitle {
            color: #a0a0a0;
            margin-bottom: 40px;
            font-size: 0.9rem;
        }
        
        .play-button {
            width: 120px;
            height: 120px;
            border-radius: 50%;
            border: none;
            background: linear-gradient(145deg, #e94560, #c73e54);
            color: white;
            font-size: 3rem;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 30px;
            box-shadow: 0 10px 40px rgba(233, 69, 96, 0.4);
            transition: transform 0.2s, box-shadow 0.2s;
        }
        
        .play-button:hover {
            transform: scale(1.05);
            box-shadow: 0 15px 50px rgba(233, 69, 96, 0.5);
        }
        
        .play-button:active {
            transform: scale(0.98);
        }
        
        .play-button.playing {
            background: linear-gradient(145deg, #4ade80, #22c55e);
            box-shadow: 0 10px 40px rgba(74, 222, 128, 0.4);
        }
        
        .play-button.playing:hover {
            box-shadow: 0 15px 50px rgba(74, 222, 128, 0.5);
        }
        
        .status {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            margin-bottom: 30px;
        }
        
        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #666;
        }
        
        .status-dot.connected {
            background: #4ade80;
            box-shadow: 0 0 10px rgba(74, 222, 128, 0.5);
        }
        
        .status-dot.connecting {
            background: #fbbf24;
            animation: pulse 1s infinite;
        }
        
        .status-dot.error {
            background: #ef4444;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .status-text {
            color: #a0a0a0;
            font-size: 0.85rem;
        }
        
        .volume-container {
            margin-top: 20px;
        }
        
        .volume-label {
            color: #a0a0a0;
            font-size: 0.8rem;
            margin-bottom: 8px;
        }
        
        .volume-slider {
            width: 80%;
            max-width: 250px;
            height: 6px;
            -webkit-appearance: none;
            background: rgba(255,255,255,0.2);
            border-radius: 3px;
            outline: none;
        }
        
        .volume-slider::-webkit-slider-thumb {
            -webkit-appearance: none;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: #e94560;
            cursor: pointer;
        }
        
        .stats {
            margin-top: 20px;
            font-size: 0.75rem;
            color: #888;
        }
        
        .stats div {
            margin: 4px 0;
        }
        
        .error-message {
            color: #ef4444;
            margin-top: 20px;
            font-size: 0.85rem;
        }
        
        .debug-log {
            margin-top: 30px;
            background: rgba(0,0,0,0.4);
            border-radius: 8px;
            padding: 12px;
            text-align: left;
            max-height: 200px;
            overflow-y: auto;
            font-family: monospace;
            font-size: 0.7rem;
            color: #888;
        }
        
        .debug-log .log-entry {
            margin: 2px 0;
            word-break: break-all;
        }
        
        .debug-log .log-info { color: #4ade80; }
        .debug-log .log-warn { color: #fbbf24; }
        .debug-log .log-error { color: #ef4444; }
        
        .copy-btn {
            margin-top: 10px;
            padding: 8px 16px;
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.2);
            border-radius: 6px;
            color: #fff;
            font-size: 0.75rem;
            cursor: pointer;
        }
        
        .copy-btn:active {
            background: rgba(255,255,255,0.2);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Cymax Audio</h1>
        <p class="subtitle">Stream audio from your Mac</p>
        
        <button class="play-button" id="playBtn" onclick="togglePlay()">
            ▶
        </button>
        
        <div class="status">
            <div class="status-dot" id="statusDot"></div>
            <span class="status-text" id="statusText">Tap to start</span>
        </div>
        
        <div class="volume-container">
            <div class="volume-label">Volume</div>
            <input type="range" class="volume-slider" id="volumeSlider" 
                   min="0" max="100" value="100" onchange="setVolume(this.value)">
        </div>
        
        <div class="stats">
            <div>WebSocket: <span id="wsStatus">Not connected</span></div>
            <div>Packets: <span id="packets">0</span></div>
            <div>Buffer: <span id="buffer">0ms</span></div>
            <div>Audio Context: <span id="audioState">Not started</span></div>
            <div>Sample Rate: <span id="sampleRate">-</span></div>
        </div>
        
        <div class="error-message" id="errorMsg"></div>
        
        <div class="debug-log" id="debugLog"></div>
        <button class="copy-btn" onclick="copyLog()">📋 Copy Log</button>
    </div>

    <script>
        const WS_HOST = '\(hostIP)';
        const WS_PORT = \(wsPort);
        
        let audioContext = null;
        let gainNode = null;
        let ws = null;
        let isPlaying = false;
        let packetsReceived = 0;
        
        // Sample rates - now DYNAMIC based on packet header
        let sourceRate = 48000;     // Will be updated from packet header
        let outputRate = 48000;     // Browser's actual rate (may differ)
        let resampleRatio = 1.0;    // outputRate / sourceRate
        let sourceRateSet = false;  // Track if we've set source rate from packet
        
        // Audio buffer (circular) - sized for output rate
        let BUFFER_SIZE = 48000 * 2; // Will resize based on output rate
        let audioBuffer = new Float32Array(BUFFER_SIZE);
        let writePos = 0;
        let readPos = 0;
        let bufferedSamples = 0;
        
        // Target buffer level (samples) - optimized for low latency
        const TARGET_BUFFER_MS = 80;   // Tight: was 85ms
        const INITIAL_PREBUFFER_MS = 5;   // Near-zero latency start
        const REBUFFER_MS = 45;           // Safe recovery after underrun
        let targetBufferSamples = 48000 * 2 * (TARGET_BUFFER_MS / 1000);
        let prebufferSamples = 48000 * 2 * (INITIAL_PREBUFFER_MS / 1000);
        let rebufferSamples = 48000 * 2 * (REBUFFER_MS / 1000);
        let isPrebuffering = true;
        let isInitialStart = true;  // Track if this is first start vs rebuffer
        
        // Debug logging
        const maxLogEntries = 50;
        function debugLog(msg, level = 'info') {
            const logDiv = document.getElementById('debugLog');
            const time = new Date().toLocaleTimeString('en-US', {hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit', fractionalSecondDigits: 3});
            const entry = document.createElement('div');
            entry.className = 'log-entry log-' + level;
            entry.textContent = '[' + time + '] ' + msg;
            logDiv.appendChild(entry);
            
            // Keep only last N entries
            while (logDiv.children.length > maxLogEntries) {
                logDiv.removeChild(logDiv.firstChild);
            }
            
            // Scroll to bottom
            logDiv.scrollTop = logDiv.scrollHeight;
            
            console.log('[Cymax] ' + msg);
        }
        
        function updateStatus(status, text) {
            const dot = document.getElementById('statusDot');
            const statusText = document.getElementById('statusText');
            
            dot.className = 'status-dot';
            if (status === 'connected') {
                dot.classList.add('connected');
            } else if (status === 'connecting') {
                dot.classList.add('connecting');
            } else if (status === 'error') {
                dot.classList.add('error');
            }
            
            statusText.textContent = text;
        }
        
        function showError(msg) {
            document.getElementById('errorMsg').textContent = msg;
            debugLog(msg, 'error');
        }
        
        function togglePlay() {
            if (isPlaying) {
                stopAudio();
            } else {
                startAudio();
            }
        }
        
        async function startAudio() {
            try {
                showError('');
                updateStatus('connecting', 'Starting...');
                debugLog('Starting audio...');
                
                // Create audio context (must be after user gesture)
                // Let browser pick its native rate - we'll resample
                audioContext = new (window.AudioContext || window.webkitAudioContext)();
                
                // Get the actual sample rate the browser is using
                outputRate = audioContext.sampleRate;
                // resampleRatio will be calculated when we receive first packet with actual source rate
                
                debugLog('AudioContext created, state: ' + audioContext.state);
                debugLog('Output rate: ' + outputRate + 'Hz (waiting for source rate from packet)');
                
                // Resize buffer for output rate (1 second is enough with low latency settings)
                BUFFER_SIZE = Math.ceil(outputRate * 2); // 1 second stereo at output rate
                audioBuffer = new Float32Array(BUFFER_SIZE);
                targetBufferSamples = Math.ceil(outputRate * 2 * (TARGET_BUFFER_MS / 1000));
                
                document.getElementById('audioState').textContent = audioContext.state;
                document.getElementById('sampleRate').textContent = outputRate + 'Hz (waiting for src)';
                
                // Resume if suspended (iOS requirement)
                if (audioContext.state === 'suspended') {
                    debugLog('Resuming suspended AudioContext...');
                    await audioContext.resume();
                    debugLog('AudioContext resumed, state: ' + audioContext.state);
                    document.getElementById('audioState').textContent = audioContext.state;
                }
                
                // Create gain node for volume control
                gainNode = audioContext.createGain();
                gainNode.connect(audioContext.destination);
                debugLog('Gain node created and connected');
                
                // Create script processor for audio output (smaller buffer = lower latency)
                const scriptNode = audioContext.createScriptProcessor(512, 0, 2);
                scriptNode.onaudioprocess = processAudio;
                scriptNode.connect(gainNode);
                debugLog('Script processor created (buffer: 512 frames, ~11ms)');
                
                // Connect WebSocket
                connectWebSocket();
                
                isPlaying = true;
                document.getElementById('playBtn').textContent = '⏸';
                document.getElementById('playBtn').classList.add('playing');
                
            } catch (err) {
                showError('Audio error: ' + err.message);
                updateStatus('error', 'Error');
                debugLog('Audio start error: ' + err.message, 'error');
            }
        }
        
        function stopAudio() {
            debugLog('Stopping audio...');
            
            if (ws) {
                ws.close();
                ws = null;
            }
            
            if (audioContext) {
                audioContext.close();
                audioContext = null;
            }
            
            isPlaying = false;
            packetsReceived = 0;
            bufferedSamples = 0;
            writePos = 0;
            readPos = 0;
            isPrebuffering = true;
            isInitialStart = true;  // Reset so next play is fast
            processCallCount = 0;
            processStartTime = 0;
            totalFramesConsumed = 0;
            
            document.getElementById('playBtn').textContent = '▶';
            document.getElementById('playBtn').classList.remove('playing');
            document.getElementById('wsStatus').textContent = 'Not connected';
            document.getElementById('audioState').textContent = 'Stopped';
            updateStatus('', 'Stopped');
            debugLog('Audio stopped');
        }
        
        function connectWebSocket() {
            const url = 'ws://' + WS_HOST + ':' + WS_PORT;
            debugLog('Connecting to WebSocket: ' + url);
            document.getElementById('wsStatus').textContent = 'Connecting...';
            
            try {
                ws = new WebSocket(url);
                ws.binaryType = 'arraybuffer';
                
                ws.onopen = () => {
                    debugLog('WebSocket connected!', 'info');
                    document.getElementById('wsStatus').textContent = 'Connected';
                    updateStatus('connected', 'Connected - Waiting for audio');
                };
                
                ws.onclose = (event) => {
                    debugLog('WebSocket closed, code: ' + event.code + ', reason: ' + event.reason, 'warn');
                    document.getElementById('wsStatus').textContent = 'Disconnected';
                    if (isPlaying) {
                        updateStatus('connecting', 'Reconnecting...');
                        setTimeout(connectWebSocket, 1000);
                    }
                };
                
                ws.onerror = (err) => {
                    debugLog('WebSocket error: ' + JSON.stringify(err), 'error');
                    document.getElementById('wsStatus').textContent = 'Error';
                    updateStatus('error', 'Connection error');
                };
                
                ws.onmessage = (event) => {
                    handleAudioPacket(event.data);
                };
            } catch (err) {
                debugLog('WebSocket creation error: ' + err.message, 'error');
            }
        }
        
        function handleAudioPacket(data) {
            packetsReceived++;
            
            if (packetsReceived === 1) {
                debugLog('First packet received! Size: ' + data.byteLength + ' bytes');
            }
            
            // Parse header (16 bytes): seq(4) + ts(4) + rate(4) + ch(2) + frames(2)
            const view = new DataView(data);
            const sequence = view.getUint32(0, true);
            const timestamp = view.getUint32(4, true);
            const packetSampleRate = view.getUint32(8, true);
            const channels = view.getUint16(12, true);
            const frameCount = view.getUint16(14, true);
            
            // #region agent log - H1 sample rate from packet
            if (packetsReceived === 1 || packetsReceived === 10) {
                fetch('http://127.0.0.1:7246/ingest/d4ebf198-e5bf-4fa0-ac15-a853e9105e0d',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'WebPlayer:handleAudioPacket',message:'PACKET_RATE',data:{packetSampleRate:packetSampleRate,sourceRate:sourceRate,outputRate:outputRate,resampleRatio:resampleRatio,sourceRateSet:sourceRateSet,packetsReceived:packetsReceived},timestamp:Date.now(),sessionId:'debug-session',hypothesisId:'H1'})}).catch(()=>{});
            }
            // #endregion
            
            // CRITICAL: Use the actual sample rate from the packet header!
            if (!sourceRateSet && packetSampleRate > 0) {
                sourceRate = packetSampleRate;
                sourceRateSet = true;
                resampleRatio = outputRate / sourceRate;
                debugLog('Source rate set from packet: ' + sourceRate + 'Hz, Ratio: ' + resampleRatio.toFixed(4));
                document.getElementById('sampleRate').textContent = outputRate + 'Hz (src:' + sourceRate + ')';
                
                // #region agent log - H1 resample ratio calculation
                fetch('http://127.0.0.1:7246/ingest/d4ebf198-e5bf-4fa0-ac15-a853e9105e0d',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'WebPlayer:handleAudioPacket',message:'RESAMPLE_CALC',data:{sourceRate:sourceRate,outputRate:outputRate,resampleRatio:resampleRatio},timestamp:Date.now(),sessionId:'debug-session',hypothesisId:'H1'})}).catch(()=>{});
                // #endregion
            }
            
            if (packetsReceived === 1) {
                debugLog('Packet header: seq=' + sequence + ', rate=' + packetSampleRate + ', ch=' + channels + ', frames=' + frameCount);
            }
            
            // Audio data starts at byte 16 (interleaved L R L R ...)
            const audioData = new Float32Array(data, 16);
            const inputFrames = audioData.length / 2; // stereo frames
            
            if (packetsReceived === 1) {
                debugLog('Audio samples: ' + audioData.length + ' (' + inputFrames + ' frames)');
                debugLog('First samples: ' + audioData.slice(0, 8).map(x => x.toFixed(4)).join(', '));
            }
            
            // #region agent log - H4 buffer state before write
            const writePosBefore = writePos;
            const bufferedBefore = bufferedSamples;
            // #endregion
            
            // Resample if needed (linear interpolation)
            if (Math.abs(resampleRatio - 1.0) > 0.001) {
                // Need to resample from sourceRate to outputRate
                const outputFrames = Math.floor(inputFrames * resampleRatio);
                
                for (let outFrame = 0; outFrame < outputFrames; outFrame++) {
                    // Map output frame to input frame (fractional)
                    const inFrameF = outFrame / resampleRatio;
                    const inFrame0 = Math.floor(inFrameF);
                    const inFrame1 = Math.min(inFrame0 + 1, inputFrames - 1);
                    const frac = inFrameF - inFrame0;
                    
                    // Interpolate left channel
                    const l0 = audioData[inFrame0 * 2];
                    const l1 = audioData[inFrame1 * 2];
                    const left = l0 + (l1 - l0) * frac;
                    
                    // Interpolate right channel
                    const r0 = audioData[inFrame0 * 2 + 1];
                    const r1 = audioData[inFrame1 * 2 + 1];
                    const right = r0 + (r1 - r0) * frac;
                    
                    // Write interleaved to buffer
                    audioBuffer[writePos] = left;
                    writePos = (writePos + 1) % BUFFER_SIZE;
                    audioBuffer[writePos] = right;
                    writePos = (writePos + 1) % BUFFER_SIZE;
                }
                
                bufferedSamples = Math.min(bufferedSamples + outputFrames * 2, BUFFER_SIZE);
            } else {
                // No resampling needed - direct copy
                for (let i = 0; i < audioData.length; i++) {
                    audioBuffer[writePos] = audioData[i];
                    writePos = (writePos + 1) % BUFFER_SIZE;
                }
                bufferedSamples = Math.min(bufferedSamples + audioData.length, BUFFER_SIZE);
            }
            
            // #region agent log - H4 detect buffer overflow
            if (packetsReceived % 500 === 0) {
                fetch('http://127.0.0.1:7246/ingest/d4ebf198-e5bf-4fa0-ac15-a853e9105e0d',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'WebPlayer:handleAudioPacket',message:'BUFFER_STATE',data:{writePosBefore:writePosBefore,writePos:writePos,readPos:readPos,bufferedBefore:bufferedBefore,bufferedSamples:bufferedSamples,BUFFER_SIZE:BUFFER_SIZE,wrapDetected:(writePos < writePosBefore)},timestamp:Date.now(),sessionId:'debug-session',hypothesisId:'H4'})}).catch(()=>{});
            }
            // #endregion
            
            // Update stats every 50 packets
            if (packetsReceived % 50 === 0) {
                const bufferMs = Math.round((bufferedSamples / 2) / outputRate * 1000);
                document.getElementById('packets').textContent = packetsReceived;
                document.getElementById('buffer').textContent = bufferMs + 'ms';
                
                if (packetsReceived % 200 === 0) {
                    debugLog('Stats: packets=' + packetsReceived + ', buffer=' + bufferMs + 'ms');
                }
            }
        }
        
        let underrunCount = 0;
        let processCallCount = 0;
        let processStartTime = 0;
        let totalFramesConsumed = 0;
        
        function processAudio(e) {
            const outputL = e.outputBuffer.getChannelData(0);
            const outputR = e.outputBuffer.getChannelData(1);
            const frameCount = outputL.length;
            
            // #region agent log - H8/H9 track playback rate
            processCallCount++;
            if (processStartTime === 0) {
                processStartTime = performance.now();
            }
            // #endregion
            
            // Check if we have enough buffered data
            const samplesNeeded = frameCount * 2; // stereo
            
            // Prebuffering phase - wait until we have enough buffer before starting
            // Use smaller threshold for initial start, larger for recovery after underrun
            const currentThreshold = isInitialStart ? prebufferSamples : rebufferSamples;
            
            if (isPrebuffering) {
                if (bufferedSamples < currentThreshold) {
                    // Still prebuffering - output silence
                    for (let i = 0; i < frameCount; i++) {
                        outputL[i] = 0;
                        outputR[i] = 0;
                    }
                    if (packetsReceived % 50 === 0) {
                        const pct = Math.round((bufferedSamples / currentThreshold) * 100);
                        const mode = isInitialStart ? 'Starting' : 'Rebuffering';
                        debugLog(mode + ': ' + pct + '% (' + Math.round(bufferedSamples/2/outputRate*1000) + 'ms)');
                    }
                    return;
                } else {
                    isPrebuffering = false;
                    isInitialStart = false;  // After first start, use rebuffer threshold
                    debugLog('Playback started with ' + Math.round(bufferedSamples/2/outputRate*1000) + 'ms buffer', 'info');
                }
            }
            
            if (bufferedSamples < samplesNeeded) {
                // Underrun - output silence and start rebuffering
                underrunCount++;
                isPrebuffering = true;  // Go back to prebuffering (will use rebufferSamples)
                debugLog('Buffer underrun #' + underrunCount + ', need ' + samplesNeeded + ', have ' + bufferedSamples + ' - rebuffering...', 'warn');
                for (let i = 0; i < frameCount; i++) {
                    outputL[i] = 0;
                    outputR[i] = 0;
                }
                return;
            }
            
            // Read interleaved samples and de-interleave
            for (let i = 0; i < frameCount; i++) {
                outputL[i] = audioBuffer[readPos];
                readPos = (readPos + 1) % BUFFER_SIZE;
                
                outputR[i] = audioBuffer[readPos];
                readPos = (readPos + 1) % BUFFER_SIZE;
            }
            
            bufferedSamples -= samplesNeeded;
            totalFramesConsumed += frameCount;
            
            // #region agent log - H8/H9 measure actual playback rate
            if (processCallCount % 100 === 0) {
                const elapsed = (performance.now() - processStartTime) / 1000;
                const effectiveRate = totalFramesConsumed / elapsed;
                const drift = totalFramesConsumed - Math.floor(elapsed * outputRate);
                const driftPct = (drift / (elapsed * outputRate)) * 100;
                debugLog('PLAYBACK_RATE: elapsed=' + elapsed.toFixed(2) + 's, frames=' + totalFramesConsumed + ', rate=' + effectiveRate.toFixed(0) + 'Hz, drift=' + driftPct.toFixed(2) + '%');
                fetch('http://127.0.0.1:7246/ingest/d4ebf198-e5bf-4fa0-ac15-a853e9105e0d',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'WebPlayer:processAudio',message:'PLAYBACK_RATE',data:{elapsed:elapsed,totalFramesConsumed:totalFramesConsumed,effectiveRate:effectiveRate,outputRate:outputRate,drift:drift,driftPct:driftPct,processCallCount:processCallCount},timestamp:Date.now(),sessionId:'debug-session',hypothesisId:'H8'})}).catch(()=>{});
            }
            // #endregion
        }
        
        function setVolume(value) {
            if (gainNode) {
                gainNode.gain.value = value / 100;
                debugLog('Volume set to ' + value + '%');
            }
        }
        
        function copyLog() {
            const logDiv = document.getElementById('debugLog');
            const entries = Array.from(logDiv.querySelectorAll('.log-entry')).map(e => e.textContent);
            const text = entries.join('\\n');
            
            if (navigator.clipboard) {
                navigator.clipboard.writeText(text).then(() => {
                    debugLog('Log copied to clipboard!');
                }).catch(err => {
                    debugLog('Copy failed: ' + err, 'error');
                    // Fallback
                    fallbackCopy(text);
                });
            } else {
                fallbackCopy(text);
            }
        }
        
        function fallbackCopy(text) {
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();
            try {
                document.execCommand('copy');
                debugLog('Log copied! (fallback)');
            } catch (e) {
                debugLog('Copy failed', 'error');
            }
            document.body.removeChild(textarea);
        }
        
        // Initial log
        debugLog('Cymax Audio Web Player loaded');
        debugLog('Will connect to ws://' + WS_HOST + ':' + WS_PORT);
        
        // Prevent screen sleep on mobile
        if ('wakeLock' in navigator) {
            navigator.wakeLock.request('screen').catch(() => {});
        }
        
        // Auto-reconnect when tab becomes visible again (mobile browsers suspend connections)
        document.addEventListener('visibilitychange', async () => {
            if (document.visibilityState === 'visible' && isPlaying) {
                debugLog('Tab became visible, checking connection...', 'info');
                
                // Check if WebSocket is dead
                const wsNeedsReconnect = !ws || ws.readyState !== WebSocket.OPEN;
                
                // Check if AudioContext is suspended (iOS does this)
                const audioNeedsResume = audioContext && audioContext.state === 'suspended';
                
                if (audioNeedsResume) {
                    debugLog('Resuming suspended AudioContext...', 'info');
                    try {
                        await audioContext.resume();
                        debugLog('AudioContext resumed: ' + audioContext.state);
                    } catch (e) {
                        debugLog('Failed to resume AudioContext: ' + e.message, 'error');
                    }
                }
                
                if (wsNeedsReconnect) {
                    debugLog('WebSocket disconnected, reconnecting...', 'warn');
                    // Reset buffer state for clean reconnect
                    bufferedSamples = 0;
                    writePos = 0;
                    readPos = 0;
                    isPrebuffering = true;
                    isInitialStart = true;
                    connectWebSocket();
                } else {
                    debugLog('Connection still active');
                }
                
                updateStatus('connected', 'Reconnected');
            }
        });
    </script>
</body>
</html>
"""
}
