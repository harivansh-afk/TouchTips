<script>
  import { page } from '$app/state';
  import '../styles.css';

  let { children } = $props();
</script>

<div class="page">
  <header>
    <a class="brand" href="/" aria-label="TouchTips home">
      <img src="/icon.png" alt="TouchTips" width="56" height="56" />
    </a>
    <nav aria-label="Information">
      <a href="/" aria-current={page.url.pathname === '/' ? 'page' : undefined}>Home</a>
      <a href="/support" aria-current={page.url.pathname === '/support' ? 'page' : undefined}>Support</a>
      <a href="/privacy" aria-current={page.url.pathname === '/privacy' ? 'page' : undefined}>Privacy</a>
    </nav>
  </header>
  <main>
    {@render children()}
    <footer>© {new Date().getFullYear()} TouchTips</footer>
  </main>
</div>
