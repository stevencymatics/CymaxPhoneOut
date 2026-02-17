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
/// - Parameter hostName: Name of the Mac (e.g. "Steven's MacBook Pro")
func getWebPlayerHTML(wsPort: UInt16, hostIP: String, hostName: String) -> String {
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <title>Cymatics Mix Link</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><circle cx='50' cy='50' r='45' fill='none' stroke='%2300d4ff' stroke-width='6'/><polygon points='40,30 40,70 72,50' fill='%2300d4ff'/></svg>">
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        
        html {
            touch-action: manipulation;
            -ms-touch-action: manipulation;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #000;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: #fff;
            padding: 10px;
            touch-action: manipulation;
            -webkit-touch-callout: none;
            -webkit-user-select: none;
            user-select: none;
            overscroll-behavior: none;
        }
        
        .container {
            text-align: center;
            max-width: 100%;
            width: 100%;
            padding: 0 10px;
            margin-top: -40px;
        }
        
        h1 {
            font-size: 2.2rem;
            margin-bottom: 8px;
            font-weight: 600;
            color: #fff;
        }
        
        .subtitle {
            color: #888;
            margin-bottom: 35px;
            font-size: 1.2rem;
        }
        
        .play-button {
            width: 130px;
            height: 130px;
            border-radius: 50%;
            border: none;
            background: linear-gradient(135deg, #00d4ff 0%, #00ffd4 100%);
            cursor: pointer;
            margin: 30px auto 35px;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 0;
            box-shadow: 0 0 30px rgba(0, 212, 255, 0.4);
        }
        
        .play-button:hover {
            background: linear-gradient(135deg, #00e5ff 0%, #00ffe5 100%);
            transform: scale(1.05);
            box-shadow: 0 0 40px rgba(0, 212, 255, 0.6);
        }
        
        .play-button:active {
            transform: scale(0.95);
        }
        
        .play-button svg {
            width: 55px;
            height: 55px;
            fill: #000;
        }
        
        .play-button .play-icon {
            margin-left: 10px; /* Optical centering for play triangle */
        }
        
        .play-button .pause-icon {
            display: none;
        }
        
        .play-button.playing .play-icon {
            display: none;
        }
        
        .play-button.playing .pause-icon {
            display: block;
        }
        
        /* Visualizer */
        .visualizer-container {
            width: 100%;
            height: 40px;
            margin: 100px 0 15px 0;
            display: flex;
            align-items: flex-end;
            justify-content: center;
            gap: 6px;
        }
        
        .viz-bar {
            width: 14px;
            min-height: 6px;
            background: linear-gradient(to top, #00d4ff, #00ffd4);
            border-radius: 3px;
            transition: height 0.05s ease-out;
        }
        
        .hidden {
            display: none !important;
        }
        
        .status {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            margin-bottom: 20px;
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
        
        .stats {
            margin-top: 30px;
            display: flex;
            align-items: flex-end;
            justify-content: center;
        }

        .signal-bars {
            display: flex;
            align-items: flex-end;
            gap: 2px;
            height: 18px;
        }

        .signal-bars .bar {
            width: 5px;
            border-radius: 1px;
            background: #333;
            transition: background 0.3s;
        }

        .signal-bars .bar:nth-child(1) { height: 5px; }
        .signal-bars .bar:nth-child(2) { height: 10px; }
        .signal-bars .bar:nth-child(3) { height: 16px; }

        .signal-bars.good .bar { background: #4ade80; }
        .signal-bars.fair .bar:nth-child(1),
        .signal-bars.fair .bar:nth-child(2) { background: #fbbf24; }
        .signal-bars.poor .bar:nth-child(1) { background: #ef4444; }

        .error-message {
            color: #ef4444;
            margin-top: 20px;
            font-size: 0.85rem;
        }
        
        /* Reconnecting overlay */
        .reconnect-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.85);
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            z-index: 1000;
            opacity: 0;
            visibility: hidden;
            transition: opacity 0.2s, visibility 0.2s;
        }
        
        .reconnect-overlay.visible {
            opacity: 1;
            visibility: visible;
        }
        
        .spinner {
            width: 50px;
            height: 50px;
            border: 4px solid #333;
            border-top-color: #00d4ff;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        .reconnect-text {
            margin-top: 20px;
            color: #888;
            font-size: 1rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Cymatics <span style="color: #00d4ff; font-weight: 700;">Mix Link</span></h1>
        <p class="subtitle" id="subtitle">Stream audio from your Computer.</p>
        
        <button class="play-button" id="playBtn" onclick="togglePlay()">
            <svg class="play-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                <polygon points="5,3 19,12 5,21"/>
            </svg>
            <svg class="pause-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                <rect x="5" y="3" width="4" height="18"/>
                <rect x="15" y="3" width="4" height="18"/>
            </svg>
        </button>
        
        <!-- Visualizer bars -->
        <div class="visualizer-container" id="visualizer">
            <div class="viz-bar" id="bar0"></div>
            <div class="viz-bar" id="bar1"></div>
            <div class="viz-bar" id="bar2"></div>
            <div class="viz-bar" id="bar3"></div>
            <div class="viz-bar" id="bar4"></div>
            <div class="viz-bar" id="bar5"></div>
            <div class="viz-bar" id="bar6"></div>
            <div class="viz-bar" id="bar7"></div>
            <div class="viz-bar" id="bar8"></div>
            <div class="viz-bar" id="bar9"></div>
            <div class="viz-bar" id="bar10"></div>
            <div class="viz-bar" id="bar11"></div>
            <div class="viz-bar" id="bar12"></div>
            <div class="viz-bar" id="bar13"></div>
            <div class="viz-bar" id="bar14"></div>
            <div class="viz-bar" id="bar15"></div>
        </div>
        
        
        <div class="stats" id="statsDisplay">
            <div class="signal-bars" id="signalBars">
                <div class="bar"></div>
                <div class="bar"></div>
                <div class="bar"></div>
            </div>
        </div>
        
        <div class="error-message" id="errorMsg"></div>
        
        <!-- Hidden stats for internal use -->
        <div style="display:none">
            <span id="wsStatus">Not connected</span>
            <span id="audioState">Not started</span>
            <span id="sampleRate">-</span>
        </div>
        
    </div>
    
    <!-- Audio element for output - routes through HTML5 audio to bypass iOS silent mode -->
    <audio id="outputAudio" playsinline style="display:none"></audio>
    
    <!-- Reconnecting overlay -->
    <div class="reconnect-overlay" id="reconnectOverlay">
        <div class="spinner"></div>
        <div class="reconnect-text">Reconnecting...</div>
    </div>

    <script>
        const WS_HOST = '\(hostIP)';
        const WS_PORT = \(wsPort);
        const HOST_NAME = '\(hostName)';
        
        let audioContext = null;
        let gainNode = null;
        let scriptNode = null;
        let mediaStreamDest = null;  // MediaStream destination for iOS silent mode bypass
        let ws = null;
        let isPlaying = false;
        let packetsReceived = 0;
        let reconnectAttempts = 0;
        
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
        const TARGET_BUFFER_MS = 40;   // Balance of low latency and WiFi jitter tolerance
        const INITIAL_PREBUFFER_MS = 5;   // Near-zero latency start
        const REBUFFER_MS = 30;           // Quick recovery after underrun
        let targetBufferSamples = 48000 * 2 * (TARGET_BUFFER_MS / 1000);
        let prebufferSamples = 48000 * 2 * (INITIAL_PREBUFFER_MS / 1000);
        let rebufferSamples = 48000 * 2 * (REBUFFER_MS / 1000);
        let isPrebuffering = true;
        let isInitialStart = true;  // Track if this is first start vs rebuffer
        
        // Visualizer state
        const NUM_BARS = 16;
        let vizBars = [];
        let vizAnimFrame = null;
        let analyserNode = null;
        let vizFreqData = null;
        let vizBarRanges = null;
        
        function initVisualizer() {
            vizBars = [];
            for (let i = 0; i < NUM_BARS; i++) {
                vizBars.push(document.getElementById('bar' + i));
            }
        }
        
        function animateVisualizer() {
            if (analyserNode && vizFreqData && vizBarRanges) {
                analyserNode.getByteFrequencyData(vizFreqData);
                for (let i = 0; i < NUM_BARS; i++) {
                    const range = vizBarRanges[i];
                    let sum = 0;
                    const count = range.high - range.low + 1;
                    for (let bin = range.low; bin <= range.high; bin++) {
                        sum += vizFreqData[bin];
                    }
                    let avg = sum / count;
                    // Boost higher frequencies to compensate for natural energy rolloff
                    avg = Math.min(255, avg * range.boost);
                    const height = Math.max(6, Math.min(40, (avg / 255) * 40));
                    if (vizBars[i]) {
                        vizBars[i].style.height = height + 'px';
                    }
                }
            }
            if (isPlaying) {
                vizAnimFrame = requestAnimationFrame(animateVisualizer);
            }
        }
        
        function resetVisualizer() {
            for (let i = 0; i < NUM_BARS; i++) {
                if (vizBars[i]) {
                    vizBars[i].style.height = '6px';
                }
            }
            if (vizAnimFrame) {
                cancelAnimationFrame(vizAnimFrame);
                vizAnimFrame = null;
            }
        }
        
        function debugLog(msg, level = 'info') {
            if (level !== 'info') console.log('[Cymax] ' + msg);
        }
        
        function updateStatus(status, text) {
            const playBtn = document.getElementById('playBtn');
            
            if (status === 'connected' || isPlaying) {
                playBtn.classList.add('playing');
            } else {
                playBtn.classList.remove('playing');
            }
        }
        
        function updateSubtitle(connected, customMessage) {
            const subtitle = document.getElementById('subtitle');
            if (connected) {
                // Connected icon (link/chain symbol)
                const connectedIcon = '<svg style="width:14px;height:14px;vertical-align:middle;margin-right:6px;" viewBox="0 0 24 24" fill="none" stroke="#4ade80" stroke-width="2.5"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>';
                subtitle.innerHTML = connectedIcon + 'Connected to <span style="color: #fff; font-weight: 600;">' + HOST_NAME + '</span>';
            } else {
                // Disconnected icon (wifi off / signal lost)
                const disconnectedIcon = '<svg style="width:14px;height:14px;vertical-align:middle;margin-right:6px;" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2.5"><circle cx="12" cy="12" r="9"/><line x1="8" y1="8" x2="16" y2="16"/></svg>';
                const message = customMessage || 'Not connected to a computer.';
                subtitle.innerHTML = disconnectedIcon + message;
            }
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
                    
                    // Use timeout - iOS can hang indefinitely without user gesture
                    const resumePromise = audioContext.resume();
                    const timeoutPromise = new Promise(resolve => setTimeout(resolve, 300));
                    
                    await Promise.race([resumePromise, timeoutPromise]);
                    
                    debugLog('AudioContext state after resume: ' + audioContext.state);
                    document.getElementById('audioState').textContent = audioContext.state;
                }
                
                // Create MediaStream destination - routes audio through HTML5 audio element
                // This bypasses iOS silent mode because <audio> elements use "playback" category
                mediaStreamDest = audioContext.createMediaStreamDestination();
                debugLog('MediaStream destination created');
                
                // Create gain node for volume control
                gainNode = audioContext.createGain();
                gainNode.connect(mediaStreamDest);  // Connect to MediaStream, not destination
                debugLog('Gain node created and connected to MediaStream');

                // Create analyser node for visualizer (FFT on live audio)
                analyserNode = audioContext.createAnalyser();
                analyserNode.fftSize = 256;  // 128 frequency bins
                analyserNode.smoothingTimeConstant = 0.65;
                vizFreqData = new Uint8Array(analyserNode.frequencyBinCount);
                analyserNode.connect(gainNode);

                // Precompute logarithmic frequency-to-bar mapping
                const binCount = analyserNode.frequencyBinCount;
                const nyquist = audioContext.sampleRate / 2;
                const minFreq = 60;
                const maxFreq = Math.min(16000, nyquist);
                vizBarRanges = [];
                for (let i = 0; i < NUM_BARS; i++) {
                    const lowFreq = minFreq * Math.pow(maxFreq / minFreq, i / NUM_BARS);
                    const highFreq = minFreq * Math.pow(maxFreq / minFreq, (i + 1) / NUM_BARS);
                    const lowBin = Math.max(0, Math.round(lowFreq / nyquist * binCount));
                    const highBin = Math.min(binCount - 1, Math.max(lowBin, Math.round(highFreq / nyquist * binCount)));
                    const boost = 1.0 + (i / (NUM_BARS - 1)) * 2.0;
                    vizBarRanges.push({ low: lowBin, high: highBin, boost: boost });
                }
                debugLog('Analyser node created (fftSize: 256, bins: ' + binCount + ', bars: ' + NUM_BARS + ' log-mapped)');

                // Create script processor for audio output (smaller buffer = lower latency)
                scriptNode = audioContext.createScriptProcessor(256, 0, 2);
                scriptNode.onaudioprocess = processAudio;
                scriptNode.connect(analyserNode);
                debugLog('Script processor created (buffer: 512 frames, ~11ms)');
                
                // Route MediaStream through HTML5 audio element (bypasses iOS silent mode)
                const outputAudio = document.getElementById('outputAudio');
                outputAudio.srcObject = mediaStreamDest.stream;
                outputAudio.play().then(() => {
                    debugLog('Audio element playing (silent mode bypass active)');
                }).catch(e => {
                    debugLog('Audio element play failed: ' + e.message, 'warn');
                });
                
                // Connect WebSocket
                connectWebSocket();
                
                isPlaying = true;
                updateStatus('connected', 'Playing');
                
                // Setup lock screen controls
                setupMediaSession();
                updateMediaSessionState(true);
                
                // Start visualizer
                initVisualizer();
                animateVisualizer();
                
            } catch (err) {
                showError('Audio error: ' + err.message);
                updateStatus('error', 'Error');
                debugLog('Audio start error: ' + err.message, 'error');
            }
        }
        
        function stopAudio() {
            debugLog('Stopping audio...');
            
            // Stop the output audio element
            try {
                const outputAudio = document.getElementById('outputAudio');
                outputAudio.pause();
                outputAudio.srcObject = null;
            } catch (e) {}
            
            // Close WebSocket if open
            if (ws) {
                ws.close();
                ws = null;
            }
            
            // Cancel HTTP stream if active
            if (httpWatchdog) {
                clearInterval(httpWatchdog);
                httpWatchdog = null;
            }
            if (httpStreamController) {
                httpStreamController.abort();
                httpStreamController = null;
            }
            if (httpStreamReader) {
                try { httpStreamReader.cancel(); } catch (e) {}
                httpStreamReader = null;
            }
            
            if (audioContext) {
                audioContext.close();
                audioContext = null;
            }

            analyserNode = null;
            vizFreqData = null;
            vizBarRanges = null;
            mediaStreamDest = null;
            
            isPlaying = false;
            packetsReceived = 0;
            bufferedSamples = 0;
            writePos = 0;
            readPos = 0;
            isPrebuffering = true;
            isInitialStart = true;  // Reset so next play is fast

            // Update lock screen state
            updateMediaSessionState(false);
            
            // Reset UI
            updateStatus('', 'Stopped');
            updateSubtitle(false);
            resetVisualizer();
            document.getElementById('wsStatus').textContent = 'Not connected';
            document.getElementById('audioState').textContent = 'Stopped';
            debugLog('Audio stopped');
        }
        
        let wsConnectionTimeout = null;
        let networkWarmedUp = false;
        
        // Safari needs HTTP request first to trigger local network permission
        async function warmUpNetwork() {
            if (networkWarmedUp) {
                debugLog('Network already warmed up, skipping');
                return true;
            }
            
            const httpUrl = 'http://' + WS_HOST + ':19621/health';
            debugLog('🌐 Network warmup: fetching ' + httpUrl);
            const warmupStart = Date.now();
            
            try {
                const response = await fetch(httpUrl, { 
                    method: 'GET',
                    cache: 'no-store'
                });
                const elapsed = Date.now() - warmupStart;
                networkWarmedUp = true;
                debugLog('🌐 Network warmup SUCCESS in ' + elapsed + 'ms (status: ' + response.status + ')');
                return true;
            } catch (err) {
                const elapsed = Date.now() - warmupStart;
                debugLog('🌐 Network warmup FAILED in ' + elapsed + 'ms: ' + err.message, 'warn');
                // Try WebSocket anyway - might still work
                return true;
            }
        }
        
        let httpStreamReader = null;
        let httpStreamController = null;
        
        // Detect Safari (iOS Safari specifically has WebSocket issues with local network)
        const isSafari = /Safari/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent);
        const isIOSSafari = isSafari && /iPhone|iPad|iPod/.test(navigator.userAgent);
        
        async function connectWebSocket() {
            // Warm up network
            await warmUpNetwork();
            
            const startTime = Date.now();
            
            // iOS Safari: ALWAYS use HTTP stream (WebSocket to local IPs is unreliable)
            if (isIOSSafari) {
                debugLog('📱 iOS Safari detected - using HTTP stream', 'info');
                connectHTTPStream();
                return;
            }
            
            const url = 'ws://' + WS_HOST + ':' + WS_PORT;
            
            debugLog('=== CONNECTION ATTEMPT ===');
            debugLog('URL: ' + url);
            debugLog('Browser: ' + (isSafari ? 'Safari' : 'Chrome/Other'));
            debugLog('User-Agent: ' + navigator.userAgent.substring(0, 80));
            debugLog('Online: ' + navigator.onLine);
            debugLog('Attempt #' + (reconnectAttempts + 1));
            document.getElementById('wsStatus').textContent = 'Connecting...';
            
            try {
                debugLog('Creating WebSocket object...');
                ws = new WebSocket(url);
                ws.binaryType = 'arraybuffer';
                debugLog('WebSocket created in ' + (Date.now() - startTime) + 'ms, readyState: ' + ws.readyState);
                
                // Timeout for connection - 2s for Safari (faster fallback), 4s for others
                const timeout = isSafari ? 2000 : 4000;
                wsConnectionTimeout = setTimeout(() => {
                    if (ws && ws.readyState === 0) {
                        const elapsed = Date.now() - startTime;
                        debugLog('⏱️ TIMEOUT after ' + elapsed + 'ms (readyState still 0)', 'warn');
                        ws.close();
                    }
                }, timeout);
                
                ws.onopen = () => {
                    clearTimeout(wsConnectionTimeout);
                    const elapsed = Date.now() - startTime;
                    debugLog('✅ WebSocket CONNECTED in ' + elapsed + 'ms!', 'info');
                    document.getElementById('wsStatus').textContent = 'Connected (WebSocket)';
                    updateStatus('connected', 'Connected - Waiting for audio');
                    updateSubtitle(true);
                    reconnectAttempts = 0;
                    useHTTPFallback = false;
                    document.getElementById('reconnectOverlay').classList.remove('visible');

                    // Flush audio buffer on reconnect — stale data causes glitches
                    writePos = 0;
                    readPos = 0;
                    bufferedSamples = 0;
                    isPrebuffering = true;
                };
                
                ws.onclose = (event) => {
                    clearTimeout(wsConnectionTimeout);
                    const elapsed = Date.now() - startTime;
                    debugLog('❌ CLOSED after ' + elapsed + 'ms - code: ' + event.code + ', wasClean: ' + event.wasClean, 'warn');
                    document.getElementById('wsStatus').textContent = 'Disconnected';

                    if (isPlaying) {
                        reconnectAttempts++;
                        // Backoff: 1s, 1s, 2s, 3s, then cap at 5s
                        const delay = reconnectAttempts <= 2 ? 1000 : Math.min(5000, reconnectAttempts * 1000);
                        debugLog('🔄 Reconnect #' + reconnectAttempts + ' in ' + delay + 'ms...', 'info');
                        document.getElementById('reconnectOverlay').classList.add('visible');
                        updateStatus('connecting', 'Reconnecting...');
                        setTimeout(connectWebSocket, delay);
                    }
                };
                
                ws.onerror = (err) => {
                    const elapsed = Date.now() - startTime;
                    debugLog('⚠️ ERROR after ' + elapsed + 'ms - readyState: ' + (ws ? ws.readyState : 'null'), 'error');
                    document.getElementById('wsStatus').textContent = 'Error';
                    updateStatus('error', 'Connection error');
                };
                
                ws.onmessage = (event) => {
                    handleAudioPacket(event.data);
                };
            } catch (err) {
                debugLog('💥 WebSocket creation EXCEPTION: ' + err.message, 'error');
            }
        }
        
        // HTTP streaming for Safari (more reliable than WebSocket on local network)
        let httpWatchdog = null;
        let lastPacketTime = 0;
        
        async function connectHTTPStream() {
            // Clean up any existing reader and watchdog
            if (httpStreamReader) {
                try {
                    await httpStreamReader.cancel();
                } catch (e) {}
                httpStreamReader = null;
            }
            if (httpWatchdog) {
                clearInterval(httpWatchdog);
                httpWatchdog = null;
            }
            
            const url = 'http://' + WS_HOST + ':' + WS_PORT + '/stream';
            debugLog('=== HTTP STREAM ===');
            debugLog('URL: ' + url);
            document.getElementById('wsStatus').textContent = 'Connecting...';
            
            try {
                const controller = new AbortController();
                httpStreamController = controller;
                
                const response = await fetch(url, {
                    method: 'GET',
                    cache: 'no-store',
                    signal: controller.signal
                });
                
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status);
                }
                
                debugLog('✅ HTTP stream connected!', 'info');
                document.getElementById('wsStatus').textContent = 'Connected';
                updateStatus('connected', 'Connected - Waiting for audio');
                updateSubtitle(true);
                reconnectAttempts = 0;
                document.getElementById('reconnectOverlay').classList.remove('visible');
                lastPacketTime = Date.now();

                // Flush audio buffer on reconnect — stale data causes glitches
                writePos = 0;
                readPos = 0;
                bufferedSamples = 0;
                isPrebuffering = true;
                
                // Watchdog: only act when stream is truly dead (long timeout)
                // Brief WiFi pauses are absorbed by the audio buffer — don't overreact
                httpWatchdog = setInterval(() => {
                    if (!isPlaying) return;
                    const staleDuration = Date.now() - lastPacketTime;
                    const bufferMs = Math.round((bufferedSamples / 2) / outputRate * 1000);

                    // Show spinner only when buffer is actually running dry
                    if (isPrebuffering && staleDuration > 500) {
                        document.getElementById('reconnectOverlay').classList.add('visible');
                        updateStatus('connecting', 'Reconnecting...');
                    } else if (!isPrebuffering) {
                        document.getElementById('reconnectOverlay').classList.remove('visible');
                    }

                    // Only kill connection after 8s of no data — server is truly gone
                    if (staleDuration > 8000) {
                        debugLog('⚠️ Stream dead - no data for 8s', 'warn');
                        clearInterval(httpWatchdog);
                        httpWatchdog = null;
                        if (httpStreamController) {
                            httpStreamController.abort();
                        }
                        handleStreamDisconnect();
                    }
                }, 500);
                
                // Read the stream
                const reader = response.body.getReader();
                httpStreamReader = reader;
                let buffer = new Uint8Array(0);
                
                while (isPlaying) {
                    const { done, value } = await reader.read();
                    if (done) {
                        debugLog('HTTP stream ended', 'warn');
                        break;
                    }
                    
                    lastPacketTime = Date.now();
                    
                    // Accumulate data
                    const newBuffer = new Uint8Array(buffer.length + value.length);
                    newBuffer.set(buffer);
                    newBuffer.set(value, buffer.length);
                    buffer = newBuffer;
                    
                    // Process complete packets
                    while (buffer.length >= 16) {
                        const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.length);
                        const frameCount = view.getUint16(14, true);
                        const channels = view.getUint16(12, true);
                        const packetSize = 16 + (frameCount * channels * 4);
                        
                        if (buffer.length >= packetSize) {
                            const packetData = new ArrayBuffer(packetSize);
                            new Uint8Array(packetData).set(buffer.subarray(0, packetSize));
                            handleAudioPacket(packetData);
                            buffer = buffer.slice(packetSize);
                        } else {
                            break;
                        }
                    }
                }
                
                // Stream ended normally
                handleStreamDisconnect();
                
            } catch (err) {
                if (err.name === 'AbortError') {
                    debugLog('HTTP stream aborted', 'info');
                    return;
                }
                debugLog('HTTP stream error: ' + err.message, 'error');
                handleStreamDisconnect();
            }
        }
        
        function handleStreamDisconnect() {
            if (httpWatchdog) {
                clearInterval(httpWatchdog);
                httpWatchdog = null;
            }

            if (isPlaying) {
                reconnectAttempts++;
                // Backoff: 1s, 1s, 2s, 3s, then cap at 5s
                const delay = reconnectAttempts <= 2 ? 1000 : Math.min(5000, reconnectAttempts * 1000);
                debugLog('🔄 Reconnect #' + reconnectAttempts + ' in ' + delay + 'ms...', 'info');
                document.getElementById('reconnectOverlay').classList.add('visible');
                updateStatus('connecting', 'Reconnecting...');
                setTimeout(connectHTTPStream, delay);
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
            
            // CRITICAL: Use the actual sample rate from the packet header!
            if (!sourceRateSet && packetSampleRate > 0) {
                sourceRate = packetSampleRate;
                sourceRateSet = true;
                resampleRatio = outputRate / sourceRate;
                debugLog('Source rate set from packet: ' + sourceRate + 'Hz, Ratio: ' + resampleRatio.toFixed(4));
                document.getElementById('sampleRate').textContent = outputRate + 'Hz (src:' + sourceRate + ')';
                
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
            
            // Update signal quality every 50 packets
            if (packetsReceived % 50 === 0) {
                const bufferMs = Math.round((bufferedSamples / 2) / outputRate * 1000);
                const bars = document.getElementById('signalBars');
                if (bufferMs > 60) {
                    bars.className = 'signal-bars good';
                } else if (bufferMs < 20) {
                    bars.className = 'signal-bars poor';
                } else {
                    bars.className = 'signal-bars fair';
                }
            }

        }
        
        let underrunCount = 0;
        
        function processAudio(e) {
            const outputL = e.outputBuffer.getChannelData(0);
            const outputR = e.outputBuffer.getChannelData(1);
            const frameCount = outputL.length;
            
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
                    // Only log prebuffer status once per second (not every callback)
                    if (packetsReceived > 0 && packetsReceived % 200 === 0) {
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
        }
        
        function setVolume(value) {
            if (gainNode) {
                gainNode.gain.value = value / 100;
                debugLog('Volume set to ' + value + '%');
            }
        }
        
        // Tab visibility - keep audio playing in background (this is a streaming app).
        // MediaSession API handles pause/play via lock screen controls instead.
        
        // Prevent screen sleep on mobile
        if ('wakeLock' in navigator) {
            navigator.wakeLock.request('screen').catch(() => {});
        }
        
        // Prevent pinch zoom
        document.addEventListener('gesturestart', function(e) { e.preventDefault(); }, { passive: false });
        document.addEventListener('gesturechange', function(e) { e.preventDefault(); }, { passive: false });
        document.addEventListener('gestureend', function(e) { e.preventDefault(); }, { passive: false });
        
        // Prevent double-tap zoom
        let lastTouchEnd = 0;
        document.addEventListener('touchend', function(e) {
            const now = Date.now();
            if (now - lastTouchEnd <= 300) { e.preventDefault(); }
            lastTouchEnd = now;
        }, { passive: false });
        
        // Media Session API - enables lock screen controls on iOS/Android
        function setupMediaSession() {
            if ('mediaSession' in navigator) {
                navigator.mediaSession.metadata = new MediaMetadata({
                    title: 'Cymatics Mix Link',
                    artist: 'Streaming from Mac',
                    album: 'System Audio',
                    artwork: [
                        { src: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect fill="%23000" width="512" height="512"/><circle cx="256" cy="256" r="180" fill="none" stroke="%2300d4ff" stroke-width="24"/><polygon points="220,160 220,352 360,256" fill="%2300d4ff"/></svg>', sizes: '512x512', type: 'image/svg+xml' }
                    ]
                });
                
                // Play action - unmute
                navigator.mediaSession.setActionHandler('play', () => {
                    debugLog('Media Session: play', 'info');
                    if (gainNode) gainNode.gain.value = 1;
                    navigator.mediaSession.playbackState = 'playing';
                    document.getElementById('playBtn').classList.add('playing');
                });
                
                // Pause action - mute
                navigator.mediaSession.setActionHandler('pause', () => {
                    debugLog('Media Session: pause', 'info');
                    if (gainNode) gainNode.gain.value = 0;
                    navigator.mediaSession.playbackState = 'paused';
                    document.getElementById('playBtn').classList.remove('playing');
                });
                
                debugLog('Media Session API configured');
            }
        }
        
        // Update media session state when playing
        function updateMediaSessionState(playing) {
            if ('mediaSession' in navigator) {
                navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
            }
        }
    </script>
</body>
</html>
"""
}
