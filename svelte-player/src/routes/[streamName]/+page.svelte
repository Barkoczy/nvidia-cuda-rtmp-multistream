<script lang="ts">
	import { PUBLIC_HLS_BASE_URL } from '$env/static/public';
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import Hls from 'hls.js';
	import {
		Play,
		Pause,
		Volume2,
		VolumeX,
		Maximize,
		Minimize,
		RefreshCw,
		AlertTriangle
	} from 'lucide-svelte';

	// Get stream name from URL parameter
	$: streamName = $page.params.streamName;

	// Player states
	let videoRef: HTMLVideoElement;
	let videoContainer: HTMLDivElement;
	let hlsInstance: Hls | null = null;
	let isLoading = true;
	let hasError = false;
	let recoveryAttempts: { [key: string]: number } = {}; // Track recovery attempts for different error types
	let errorMessage = '';
	let isPlaying = false;
	let isMuted = false;
	let volume = 1;
	let isFullscreen = false;
	let isBuffering = false;
	let progress = 0;
	let duration = 0;
	let currentTime = 0;
	let bufferEnd = 0;
	let qualityLevels: { id: number; height: number; bitrate: number }[] = [];
	let currentQuality = 'auto';
	let lastInitializedStream = '';

	// Responsive player settings
	let containerWidth: number;
	$: aspectRatio = 16 / 9;
	$: containerHeight = containerWidth / aspectRatio;

	// Stream URL based on streamName
	$: streamUrl = streamName ? `${PUBLIC_HLS_BASE_URL}/${streamName}.m3u8` : '';

	const formatTime = (seconds: number) => {
		if (isNaN(seconds) || seconds < 0) return '00:00';
		const mins = Math.floor(seconds / 60);
		const secs = Math.floor(seconds % 60);
		return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
	};

	function initPlayer() {
		if (!streamName || !videoRef) return;

		isLoading = true;
		hasError = false;

		// Check if HLS.js is supported
		if (Hls.isSupported()) {
			// Destroy previous instance if exists
			if (hlsInstance) {
				hlsInstance.destroy();
				hlsInstance = null;
			}

			// Create new HLS instance with optimized stability settings
			hlsInstance = new Hls({
				enableWorker: true, // Enables web worker for background processing
				lowLatencyMode: false, // Disabled for better stability
				backBufferLength: 120, // Larger buffer for rewind capability (seconds)
				liveSyncDuration: 12, // Target buffer ahead of current position (seconds)
				liveMaxLatencyDuration: 60, // Maximum latency allowed before catching up
				liveDurationInfinity: true, // Treats live streams as having infinite duration
				highBufferWatchdogPeriod: 8, // How often to check if player is stuck (seconds)
				fragLoadingTimeOut: 90000, // Timeout for fragment loading (ms)
				manifestLoadingTimeOut: 90000, // Timeout for playlist/manifest loading (ms)
				levelLoadingTimeOut: 90000, // Timeout for level playlist loading (ms)
				maxBufferLength: 300, // Maximum buffer length in seconds
				maxBufferSize: 150 * 1000 * 1000, // Maximum buffer size in bytes (150MB)
				startLevel: -1, // Start with auto quality selection
				autoStartLoad: true, // Automatically start loading media
				maxMaxBufferLength: 600, // Absolute maximum buffer length (seconds)

				// Adaptive Bitrate strategy parameters
				abrEwmaDefaultEstimate: 1000000, // Default bandwidth estimate (bits/s)
				abrEwmaFastLive: 2.0, // Fast averaging weight (slower adaptation)
				abrEwmaSlowLive: 15.0, // Slow averaging weight (more stable quality)
				startFragPrefetch: true, // Prefetch first fragment for faster startup

				// Error recovery parameters
				nudgeMaxRetry: 20, // Maximum attempts to recover from stalls
				nudgeOffset: 0.5, // How far to skip forward when recovering (seconds)
				maxFragLookUpTolerance: 0.5, // Tolerance when matching media to fragments (seconds)
				maxLoadingDelay: 8, // Max time to wait before abandoning slow fragment (seconds)

				// Additional stability parameters
				maxStarvationDelay: 8000, // Maximum delay before starvation (ms)
				// Removed maxLevelCappingDelay as it does not exist in HlsConfig
				fragLoadPolicy: {
					default: {
						maxTimeToFirstByteMs: 30000, // Maximum time to first byte of fragment
						maxLoadTimeMs: 180000, // Maximum time to load fragment
						timeoutRetry: { maxNumRetry: 3, retryDelayMs: 1000, maxRetryDelayMs: 5000 }, // Number of retries for timeout errors
						errorRetry: { maxNumRetry: 3, retryDelayMs: 1000, maxRetryDelayMs: 5000 } // Number of retries for other errors
					}
				},
				appendErrorMaxRetry: 5 // Maximum retries when appending segments
			});

			// Add event listeners
			hlsInstance.on(Hls.Events.MEDIA_ATTACHED, () => {
				console.log('HLS media attached');
			});

			hlsInstance.on(Hls.Events.MANIFEST_PARSED, (event, data) => {
				console.log('HLS manifest parsed');
				isLoading = false;

				// Get available quality levels
				if (data.levels && data.levels.length > 0) {
					qualityLevels = data.levels.map((level, index) => ({
						id: index,
						height: level.height,
						bitrate: level.bitrate
					}));
				}

				// Detekcia mobilných zariadení
				const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
					navigator.userAgent
				);

				// Nastavenie počiatočnej kvality pre mobilné zariadenia
				if (isMobile && hlsInstance) {
					hlsInstance.startLevel = 2; // Nastaví najnižšiu kvalitu pre mobilné zariadenia
					// Prípadne môžeme nastaviť aj nižší volume
					if (videoRef) videoRef.volume = 0.5;
				}

				videoRef.play().catch((error) => {
					console.error('Auto-play failed:', error);
					// Try with muted if autoplay fails
					videoRef.muted = true;
					isMuted = true;
					videoRef.play().catch((e) => console.error('Muted autoplay failed too:', e));
				});
			});

			hlsInstance.on(Hls.Events.ERROR, (event, data) => {
				console.error('HLS error:', data);

				// If not fatal, just log and continue
				if (!data.fatal) {
					// Special handling for bufferStalledError
					if (data.details === 'bufferStalledError') {
						// Hide buffering indicator after short delay
						setTimeout(() => {
							isBuffering = false;
						}, 1000);
					}
					console.log('Non-fatal error, continuing playback');
					return;
				}

				// Set recovery attempt counter for different error types
				const maxRecoveryAttempts = 3;
				const recoveryKey = `${data.type}_${data.details}`;
				recoveryAttempts[recoveryKey] = (recoveryAttempts[recoveryKey] || 0) + 1;

				if (recoveryAttempts[recoveryKey] <= maxRecoveryAttempts) {
					switch (data.type) {
						case Hls.ErrorTypes.NETWORK_ERROR:
							console.log(
								`Recovery attempt ${recoveryAttempts[recoveryKey]}/${maxRecoveryAttempts} for network error`
							);
							hlsInstance?.startLoad();
							break;
						case Hls.ErrorTypes.MEDIA_ERROR:
							console.log(
								`Recovery attempt ${recoveryAttempts[recoveryKey]}/${maxRecoveryAttempts} for media error`
							);
							hlsInstance?.recoverMediaError();
							break;
						default:
							// Unrecoverable error
							hasError = true;
							errorMessage = `Fatal error: ${data.details}`;
							hlsInstance?.destroy();
							break;
					}
				} else {
					// We've exhausted recovery attempts
					hasError = true;
					errorMessage = `Could not recover after ${maxRecoveryAttempts} attempts: ${data.details}`;
					hlsInstance?.destroy();
				}
			});

			hlsInstance.on(Hls.Events.BUFFER_APPENDING, () => {
				isBuffering = true;
			});

			hlsInstance.on(Hls.Events.FRAG_BUFFERED, () => {
				isBuffering = false;
				if (videoRef && videoRef.buffered.length) {
					bufferEnd = videoRef.buffered.end(videoRef.buffered.length - 1);
				}
			});

			// Attach media and load source
			hlsInstance.attachMedia(videoRef);
			hlsInstance.loadSource(streamUrl);
		} else if (videoRef.canPlayType('application/vnd.apple.mpegurl')) {
			// For Safari which has native HLS support
			videoRef.src = streamUrl;
			videoRef.addEventListener('loadedmetadata', () => {
				isLoading = false;
				videoRef.play().catch((error) => {
					console.error('Auto-play failed:', error);
					// Try with muted if autoplay fails
					videoRef.muted = true;
					isMuted = true;
					videoRef.play().catch((e) => console.error('Muted autoplay failed too:', e));
				});
			});

			videoRef.addEventListener('error', () => {
				hasError = true;
				errorMessage = 'Video loading failed';
				isLoading = false;
			});
		} else {
			hasError = true;
			errorMessage = 'HLS is not supported in your browser';
			isLoading = false;
		}
	}

	function togglePlay() {
		if (!videoRef) return;

		if (videoRef.paused) {
			videoRef.play();
		} else {
			videoRef.pause();
		}
	}

	function toggleMute() {
		if (!videoRef) return;

		videoRef.muted = !videoRef.muted;
		isMuted = videoRef.muted;
	}

	function handleVolumeChange(event: Event) {
		if (!videoRef) return;

		const target = event.target as HTMLInputElement | null;
		if (target) {
			volume = parseFloat(target.value);
		}
		videoRef.volume = volume;

		// Auto-unmute when increasing volume from zero
		if (volume > 0 && isMuted) {
			toggleMute();
		}
	}

	function toggleFullscreen() {
		if (!videoContainer) return;

		if (!document.fullscreenElement) {
			videoContainer.requestFullscreen().catch((err) => {
				console.error(`Error attempting to enable fullscreen: ${err.message}`);
			});
		} else {
			document.exitFullscreen();
		}
	}

	function setQualityLevel(level: string | number) {
		if (!hlsInstance) return;

		if (level === 'auto') {
			hlsInstance.currentLevel = -1; // Auto
			currentQuality = 'auto';
		} else {
			hlsInstance.currentLevel = parseInt(level.toString());
			currentQuality = level.toString();
		}
	}

	function handleTimeUpdate() {
		if (!videoRef) return;

		currentTime = videoRef.currentTime;
		duration = videoRef.duration || 0;

		if (duration > 0) {
			progress = (currentTime / duration) * 100;
		}
	}

	function refreshStream() {
		if (hlsInstance) {
			isLoading = true;
			hlsInstance.stopLoad();
			hlsInstance.startLoad();

			// Force reload after a short delay if the stream doesn't recover
			setTimeout(() => {
				if (isLoading) {
					initPlayer();
				}
			}, 3000);
		} else {
			initPlayer();
		}

		// Reset recovery attempts counter
		recoveryAttempts = {};
	}

	// Event handlers
	function handlePlayEvent() {
		isPlaying = true;
	}

	function handlePauseEvent() {
		isPlaying = false;
	}

	function handleFullscreenChange() {
		isFullscreen = !!document.fullscreenElement;
	}

	function handleWaiting() {
		isBuffering = true;
	}

	function handlePlaying() {
		isBuffering = false;
	}

	function handleCanPlay() {
		isLoading = false;
	}

	function setupEventListeners() {
		if (!videoRef) return;

		videoRef.addEventListener('play', handlePlayEvent);
		videoRef.addEventListener('pause', handlePauseEvent);
		videoRef.addEventListener('timeupdate', handleTimeUpdate);
		videoRef.addEventListener('waiting', handleWaiting);
		videoRef.addEventListener('playing', handlePlaying);
		videoRef.addEventListener('canplay', handleCanPlay);
		document.addEventListener('fullscreenchange', handleFullscreenChange);
	}

	function cleanupEventListeners() {
		if (!videoRef) return;

		videoRef.removeEventListener('play', handlePlayEvent);
		videoRef.removeEventListener('pause', handlePauseEvent);
		videoRef.removeEventListener('timeupdate', handleTimeUpdate);
		videoRef.removeEventListener('waiting', handleWaiting);
		videoRef.removeEventListener('playing', handlePlaying);
		videoRef.removeEventListener('canplay', handleCanPlay);
		document.removeEventListener('fullscreenchange', handleFullscreenChange);
	}

	onMount(() => {
		if (videoRef) {
			// Initialize player when component mounts
			initPlayer();
			setupEventListeners();
		}
	});

	onDestroy(() => {
		// Clean up when component is destroyed
		if (hlsInstance) {
			hlsInstance.destroy();
		}

		cleanupEventListeners();
	});

	// Watch for stream name changes and re-initialize player
	$: if (streamName && videoRef && streamName !== lastInitializedStream) {
		lastInitializedStream = streamName;
		initPlayer();
	}
</script>

<svelte:head>
	<title>Live Stream - {streamName || 'Not Found'}</title>
</svelte:head>

<div class="mx-auto max-w-6xl">
	<div class="mb-4">
		<a
			href="/"
			class="inline-flex items-center gap-1 text-gray-400 transition-colors hover:text-white"
		>
			&larr; Späť na zoznam streamov
		</a>
	</div>

	{#if !streamName}
		<div class="rounded-lg border border-red-800 bg-red-900/30 p-6">
			<h2 class="mb-2 text-xl font-semibold text-red-400">Stream nenájdený</h2>
			<p class="text-gray-300">Prosím, zadajte platný názov streamu.</p>
		</div>
	{:else}
		<div class="overflow-hidden rounded-lg bg-gray-900 shadow-xl">
			<h1 class="border-b border-gray-800 p-4 text-xl font-bold">
				{streamName}
				<span class="ml-2 rounded-full bg-red-600 px-2 py-0.5 text-xs">LIVE</span>
			</h1>

			<div
				class="video-container relative bg-black"
				style="height: {containerHeight}px"
				bind:this={videoContainer}
				bind:clientWidth={containerWidth}
			>
				<!-- Video Player -->
				<!-- svelte-ignore a11y_media_has_caption -->
				<video
					bind:this={videoRef}
					class="h-full w-full cursor-pointer"
					playsinline
					on:click={togglePlay}
					class:opacity-0={isLoading || hasError}
				></video>

				<!-- Loading Indicator -->
				{#if isLoading}
					<div class="absolute inset-0 flex flex-col items-center justify-center bg-black/70">
						<div
							class="mb-4 h-12 w-12 animate-spin rounded-full border-4 border-red-500 border-t-transparent"
						></div>
						<p class="text-gray-200">Načítavanie streamu...</p>
					</div>
				{/if}

				<!-- Buffering Indicator -->
				{#if isBuffering && !isLoading}
					<div
						class="absolute bottom-20 right-4 flex items-center gap-1.5 rounded-lg bg-black/80 px-3 py-1.5 text-sm"
					>
						<div
							class="h-4 w-4 animate-spin rounded-full border-2 border-gray-500 border-t-red-500"
						></div>
						<span>Buffering...</span>
					</div>
				{/if}

				<!-- Error Message -->
				{#if hasError}
					<div
						class="absolute inset-0 flex flex-col items-center justify-center bg-black/90 p-6 text-center"
					>
						<AlertTriangle size={48} class="mb-4 text-red-500" />
						<h3 class="mb-2 text-xl font-bold text-white">Chyba pri načítaní streamu</h3>
						<p class="mb-6 text-gray-300">{errorMessage}</p>
						<button
							on:click={refreshStream}
							class="flex items-center gap-2 rounded-lg bg-red-600 px-4 py-2 hover:bg-red-700"
						>
							<RefreshCw size={16} />
							Skúsiť znova
						</button>
					</div>
				{/if}

				<!-- Player Controls -->
				<div
					class="player-controls absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 to-transparent px-4 pb-4 pt-12"
				>
					<!-- Progress bar -->
					<div class="relative mb-4 h-1 w-full cursor-pointer rounded-full bg-gray-700">
						<div
							class="absolute left-0 top-0 h-full rounded-full bg-red-600"
							style="width: {progress}%"
						></div>
						<div
							class="absolute left-0 top-0 h-full rounded-full bg-gray-600/50"
							style="width: {(bufferEnd / (duration || 1)) * 100}%"
						></div>
					</div>

					<div class="flex items-center gap-4">
						<!-- Play/Pause button -->
						<button
							class="text-white transition-colors hover:text-red-500"
							on:click={togglePlay}
							aria-label={isPlaying ? 'Pozastaviť' : 'Prehrať'}
						>
							{#if isPlaying}
								<Pause size={24} />
							{:else}
								<Play size={24} />
							{/if}
						</button>

						<!-- Volume control -->
						<div class="flex items-center gap-2">
							<button
								class="text-white transition-colors hover:text-red-500"
								on:click={toggleMute}
								aria-label={isMuted ? 'Zapnúť zvuk' : 'Stlmiť'}
							>
								{#if isMuted || volume === 0}
									<VolumeX size={20} />
								{:else}
									<Volume2 size={20} />
								{/if}
							</button>

							<input
								type="range"
								min="0"
								max="1"
								step="0.01"
								class="slider w-20 md:w-32"
								value={volume}
								on:input={handleVolumeChange}
								disabled={isMuted}
							/>
						</div>

						<!-- Time display -->
						<div class="ml-auto hidden text-sm text-gray-300 sm:block">
							<span>{formatTime(currentTime)}</span>
							<span class="mx-1">/</span>
							<span>LIVE</span>
						</div>

						<!-- Quality selector (if multiple qualities available) -->
						{#if qualityLevels.length > 0}
							<div class="relative hidden sm:block">
								<select
									class="rounded bg-gray-800 px-2 py-1 text-sm"
									value={currentQuality}
									on:change={(e) => {
										const target = e.target as HTMLSelectElement | null;
										if (target) {
											setQualityLevel(target.value);
										}
									}}
								>
									<option value="auto">Auto</option>
									{#each qualityLevels as level}
										<option value={level.id}>{level.height}p</option>
									{/each}
								</select>
							</div>
						{/if}

						<!-- Refresh button -->
						<button
							class="text-white transition-colors hover:text-red-500"
							on:click={refreshStream}
							aria-label="Obnoviť stream"
						>
							<RefreshCw size={20} />
						</button>

						<!-- Fullscreen button -->
						<button
							class="text-white transition-colors hover:text-red-500"
							on:click={toggleFullscreen}
							aria-label={isFullscreen ? 'Ukončiť celú obrazovku' : 'Celá obrazovka'}
						>
							{#if isFullscreen}
								<Minimize size={20} />
							{:else}
								<Maximize size={20} />
							{/if}
						</button>
					</div>
				</div>
			</div>

			<div class="border-t border-gray-800 p-4">
				<h2 class="mb-2 text-xl font-bold">{streamName}</h2>
				<p class="text-gray-400">
					Low-latency HLS stream powered by NVIDIA NVENC hardware acceleration
				</p>
			</div>
		</div>

		<!-- Stream Information -->
		<div class="mt-6 grid grid-cols-1 gap-6 md:grid-cols-2">
			<div class="rounded-lg bg-gray-800/70 p-4">
				<h3 class="mb-3 text-lg font-semibold">Stream Info</h3>
				<div class="space-y-2 text-sm">
					<div class="flex justify-between border-b border-gray-700 pb-2">
						<span class="text-gray-400">Source</span>
						<span>RTMP</span>
					</div>
					<div class="flex justify-between border-b border-gray-700 pb-2">
						<span class="text-gray-400">Protocol</span>
						<span>LL-HLS</span>
					</div>
					<div class="flex justify-between border-b border-gray-700 pb-2">
						<span class="text-gray-400">Encoding</span>
						<span>NVIDIA NVENC</span>
					</div>
					<div class="flex justify-between">
						<span class="text-gray-400">Latency</span>
						<span>Ultra Low (~1-3s)</span>
					</div>
				</div>
			</div>

			<div class="rounded-lg bg-gray-800/70 p-4">
				<h3 class="mb-3 text-lg font-semibold">How to Stream</h3>
				<p class="mb-3 text-gray-400">
					Stream to this channel using your favorite streaming software:
				</p>
				<div class="mb-3 overflow-x-auto rounded bg-gray-900 p-3 font-mono text-sm">
					rtmp://localhost:1935/live/{streamName}
				</div>
				<p class="text-sm text-gray-400">
					Set your encoder to use H.264 for maximum compatibility.
				</p>
			</div>
		</div>
	{/if}
</div>

<style>
	.video-container:hover .player-controls {
		opacity: 1;
	}

	.player-controls {
		opacity: 0;
		transition: opacity 0.3s ease;
	}

	.slider {
		-webkit-appearance: none;
		appearance: none;
		width: 100%;
		height: 3px;
		border-radius: 5px;
		background: #636363;
		outline: none;
	}

	.slider::-webkit-slider-thumb {
		-webkit-appearance: none;
		appearance: none;
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: #ff0000;
		cursor: pointer;
	}

	.slider::-moz-range-thumb {
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: #ff0000;
		cursor: pointer;
		border: none;
	}
</style>
