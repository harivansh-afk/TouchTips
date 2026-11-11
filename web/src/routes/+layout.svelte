<script>
  import { page } from '$app/state';
  import '../styles.css';

  let { children } = $props();
  const path = $derived(page.url.pathname.replace(/\/$/, '') || '/');
  const wide = $derived(path === '/' || path === '/connect');
</script>

<header class="top">
  <nav class="wrap" aria-label="Site">
    <span class="left">{#if path !== '/'}<a href="/">Home</a>{/if}</span>
    <span class="right">
      <a href="/privacy" aria-current={path === '/privacy' ? 'page' : undefined}>Privacy</a>
      <a href="/support" aria-current={path === '/support' ? 'page' : undefined}>Support</a>
      <a class="gh" href="https://github.com/harivansh-afk/TouchTips" aria-label="Source on GitHub"><span class="ico" style="--i:url(/agents/github.svg)"></span></a>
    </span>
  </nav>
</header>

<main class="wrap" class:narrow={!wide}>
  {@render children()}
</main>

<footer>
  <div class="wrap">
    <a class="app" href="/ios" aria-label="Get TouchTips on the App Store">
      <img src="/app-icon.png" alt="" width="132" height="132" />
    </a>
    <div class="word serif" aria-hidden="true">TouchTips</div>
  </div>
</footer>
