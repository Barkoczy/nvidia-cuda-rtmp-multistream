<script lang="ts">
	import '../app.css';
	let { children } = $props();
</script>

<div class="min-h-screen bg-black text-white">
	<main class="container mx-auto p-4">
	  {@render children()}
	</main>
  </div>
