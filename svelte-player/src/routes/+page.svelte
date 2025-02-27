<script lang="ts">
    import { onMount } from 'svelte';
    import { Search, Video, AlertCircle } from 'lucide-svelte';
    import { PUBLIC_RTMP_STAT_URL } from '$env/static/public';
    
    let streams: string[] = [];
    let isLoading = true;
    let error = '';
    let searchQuery = '';
    
    $: filteredStreams = streams.filter(stream => 
      stream.toLowerCase().includes(searchQuery.toLowerCase())
    );
    
    onMount(async () => {
      try {
        // Attempt to access NGINX RTMP server stats
        const response = await fetch(PUBLIC_RTMP_STAT_URL);
        
        if (response.ok) {
          const text = await response.text();
          // Simple regex to find stream names in rtmp stat XML
          const matches = text.match(/name="([^"]+)"/g);
          if (matches) {
            streams = matches
              .map(m => m.replace('name="', '').replace('"', ''))
              .filter(n => n !== 'live'); // Filter out application name
          }
        } else {
          error = 'Failed to load streams. Server returned: ' + response.status;
        }
      } catch (e) {
        error = 'Error connecting to RTMP server stats';
        console.error(e);
      } finally {
        isLoading = false;
      }
    });
</script>

<svelte:head>
  <title>HLS Player - Low Latency Streams</title>
</svelte:head>

<div class="mx-auto max-w-6xl">
  <header class="mb-8">
    <h1 class="mb-4 text-3xl font-bold md:text-4xl">Low-Latency HLS Streamy</h1>
    <p class="text-gray-400">Streamujte obsah s extrémne nízkou latenciou</p>
  </header>
  
  {#if isLoading}
    <div class="flex h-64 items-center justify-center">
      <div
        class="h-10 w-10 animate-spin rounded-full border-4 border-red-500 border-t-transparent"
      ></div>
    </div>
  {:else if error}
    <div class="flex items-start gap-4 rounded-lg border border-red-800 bg-red-900/30 p-6">
      <AlertCircle class="mt-1 flex-shrink-0 text-red-500" size={24} />
      <div>
        <h2 class="mb-2 text-xl font-semibold text-red-400">Chyba pripojenia</h2>
        <p class="mb-4 text-gray-300">{error}</p>
        <div class="mb-4 rounded-lg bg-gray-800 p-4">
          <p class="mb-2 text-gray-300">
            Môžete stále pristupovať k streamom priamo zadaním názvu streamu v URL:
          </p>
          <code class="block rounded bg-gray-900 p-2 font-mono text-sm"
            >http://localhost:3000/[stream-name]</code
          >
        </div>
      </div>
    </div>
  {:else}
    <div class="relative mb-6">
      <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
        <Search size={20} class="text-gray-400" />
      </div>
      <input
        type="text"
        bind:value={searchQuery}
        placeholder="Hľadať streamy..."
        class="w-full rounded-lg border border-gray-700 bg-gray-800 py-2 pl-10 pr-4 text-white focus:outline-none focus:ring-2 focus:ring-red-500"
      />
    </div>
    
    {#if streams.length === 0}
      <div class="rounded-lg border border-gray-700 bg-gray-800/50 p-6">
        <h2 class="mb-4 flex items-center gap-2 text-xl font-semibold">
          <Video size={24} />
          Žiadne aktívne streamy
        </h2>
        <p class="mb-4 text-gray-300">
          Momentálne nie sú dostupné žiadne streamy. Začnite streamovať pomocou RTMP:
        </p>
        <div class="mb-4 rounded-lg bg-gray-800 p-3">
          <code class="font-mono text-sm">rtmp://localhost:1935/live/[nazov-streamu]</code>
        </div>
        <p class="mb-2 text-gray-300">Potom navštívte:</p>
        <div class="rounded-lg bg-gray-800 p-3">
          <code class="font-mono text-sm">http://localhost:3000/[nazov-streamu]</code>
        </div>
      </div>
    {:else}
      <div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
        {#each filteredStreams as stream}
          <a
            href="/{stream}"
            class="flex flex-col overflow-hidden rounded-lg bg-gray-800 transition-colors hover:bg-gray-700"
          >
            <div class="flex aspect-video items-center justify-center bg-gray-900">
              <Video size={48} class="text-gray-600" />
            </div>
            <div class="p-4">
              <h3 class="truncate text-xl font-semibold">{stream}</h3>
              <p class="text-sm text-gray-400">Live Stream</p>
            </div>
          </a>
        {/each}
      </div>
      
      {#if filteredStreams.length === 0 && searchQuery}
        <div class="py-12 text-center text-gray-400">
          <p>Žiadne streamy nezodpovedajú vyhľadávaniu "{searchQuery}"</p>
        </div>
      {/if}
    {/if}
  {/if}
  
  <footer class="mt-16 border-t border-gray-800 pt-6 text-sm text-gray-500">
    <p>NVIDIA NVENC Accelerated LL-HLS Player</p>
  </footer>
</div>