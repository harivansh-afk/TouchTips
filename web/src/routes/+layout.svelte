<script>
  import { page } from '$app/state';
  import '../styles.css';

  let { children } = $props();
  const path = $derived(page.url.pathname.replace(/\/$/, '') || '/');
  const wide = $derived(path === '/' || path === '/connect');
</script>

<header class="top">
  <nav class="wrap" aria-label="Site">
    {#if path !== '/'}<a href="/">Home</a>{/if}
    <a href="/connect" aria-current={path.startsWith('/connect') ? 'page' : undefined}>Connect</a>
  </nav>
</header>

<main class="wrap" class:narrow={!wide}>
  {@render children()}
</main>

<footer>
  <div class="wrap">
    <a class="app" href="/ios">
      <img src="/app-icon.png" alt="" width="132" height="132" />
      <span>Download for iPhone</span>
    </a>
    <nav aria-label="Footer">
      <a href="/privacy">Privacy</a>
      <a href="/support">Support</a>
      <a href="https://github.com/harivansh-afk/TouchTips">Source</a>
    </nav>
    <div class="word serif" aria-hidden="true">TouchTips</div>
  </div>
</footer>
